-- QSPI memory initialisation: reset, ID check, configuration, quad-path check
--
--   Runs after reset_n is released and again on init_restart (only accepted when done or
--   failed). Drives qspi_xact through its command port (cmd_*, tx_* and rx_*).
--   Sequence (documentation/device_facts.md §4.3):
--     W25Q128JV: wait tPUW -> 66h, 99h -> wait tRST -> 9Fh = EF 40 18 -> SR1: nothing protected,
--                SR2: CMP = 0 and QE = 1 (fixed on the -IQ part), SR3: WPS = 0 -> EBh read.
--                The status registers are never written.
--     AS308G208: RESET# low -> wait tPU -> 9Fh (both dies) -> WREN + WRAR CR2 = 08h (latency 8)
--                -> WREN + WRSR SR = 00h (no protection) -> RDAR CR2 = 08h, RDAR CR1 WRENS = 00
--                (WREN needed before every write), RDSR: no protection -> EBh read.
--                The registers are always written, because their volatility is not documented
--                (Q-A3) and RDAR itself depends on CR2.
--   With DIE2_PRESENT every check covers both dies. 9Fh and 05h run at SCLK <= the device's
--   limit for them (40 MHz on the AS308G208); everything else at CLK_HZ / (2 * SCLK_DIV).
--   The final EBh read (8 host bytes from address 0) checks that the quad path completes; its
--   data is not compared.
--
--   init_done: sequence finished without error. init_err: a check failed; err_code says which
--   (ERR_ID: wrong ID on a die, ERR_CFG: register check). Both stay until the next run.
--   step: the current step number (for SmartDebug / status).
--
--   Time generics set to 0 use the datasheet values from qspi_pkg.

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.util_pkg.all;
use work.qspi_pkg.all;

entity qspi_init is
    generic (
        DEVICE         : device_t := DEV_W25Q128JV;
        DIE2_PRESENT   : boolean  := false;
        CLK_HZ         : positive := 100_000_000; -- Input clock frequency
        SCLK_DIV       : positive := 1;           -- Normal SCLK divider
        T_POWERUP_NS   : natural  := 0;           -- W25Q tPUW / AS tPU
        T_RESET_NS     : natural  := 0            -- W25Q tRST / AS RESET# low time
    );
    port (
        clk            : in  std_logic;
        reset_n        : in  std_logic;           -- Synchronous, active low

        init_restart   : in  std_logic;           -- Pulse: run the sequence again
        init_done      : out std_logic;
        init_err       : out std_logic;
        err_code       : out std_logic_vector(1 downto 0);
        step           : out std_logic_vector(4 downto 0);

        mem_reset_n    : out std_logic;           -- AS308G208 RESET# (always '1' for the W25Q)

        -- Command port to qspi_xact
        cmd_valid      : out std_logic;
        cmd_ready      : in  std_logic;
        cmd_op         : out std_logic_vector(7 downto 0);
        cmd_lanes      : out cmd_lanes_t;
        cmd_addr       : out std_logic_vector(31 downto 0);
        cmd_addr_bytes : out natural range 0 to 4;
        cmd_mode_en    : out std_logic;
        cmd_mode       : out std_logic_vector(7 downto 0);
        cmd_latency    : out natural range 0 to 15;
        cmd_dir        : out dir_t;
        cmd_len        : out unsigned(15 downto 0);
        cmd_sclk_div   : out natural range 1 to SCLK_DIV_MAX;
        cmd_write      : out std_logic;
        xact_busy      : in  std_logic;

        tx_tdata       : out std_logic_vector(7 downto 0);
        tx_tvalid      : out std_logic;
        tx_tready      : in  std_logic;

        rx_tdata       : in  std_logic_vector(7 downto 0);
        rx_tvalid      : in  std_logic;
        rx_tready      : out std_logic;
        rx_tlast       : in  std_logic
    );
end entity qspi_init;

architecture rtl of qspi_init is

    constant P   : dev_params_t := dev_params(DEVICE);
    constant W25 : boolean := DEVICE = DEV_W25Q128JV;

    function pick(v, dflt : natural) return natural is
    begin
        if v = 0 then
            return dflt;
        end if;
        return v;
    end function;

    constant N_POWERUP : natural := ns_to_cycles(pick(T_POWERUP_NS, P.t_powerup_ns), CLK_HZ);
    constant N_RESET   : natural := ns_to_cycles(pick(T_RESET_NS, P.t_reset_ns), CLK_HZ);
    -- Divider for 05h / 9Fh: SCLK <= slow_sclk_hz
    constant SLOW_DIV  : positive := maximum(SCLK_DIV,
                                             (CLK_HZ + 2 * P.slow_sclk_hz - 1) / (2 * P.slow_sclk_hz));
    constant DIES      : positive := 1 + boolean'pos(DIE2_PRESENT);

    constant ERR_NONE  : std_logic_vector(1 downto 0) := "00";
    constant ERR_ID    : std_logic_vector(1 downto 0) := "01";
    constant ERR_CFG   : std_logic_vector(1 downto 0) := "10";

    type step_t is (
        S_IDLE,
        -- W25Q128JV
        S_W_PU, S_W_RSTEN, S_W_RST, S_W_RSTWAIT, S_W_ID, S_W_SR1, S_W_SR2, S_W_SR3,
        -- AS308G208
        S_A_RESET, S_A_PU, S_A_ID, S_A_WREN1, S_A_CR2W, S_A_WREN2, S_A_SRW,
        S_A_CR2R, S_A_CR1R, S_A_SRR,
        -- Both
        S_QREAD, S_DONE, S_ERROR);

    -- Within a step: wait, issue the command, send TX bytes, receive RX bytes, check
    type sub_t is (U_WAIT, U_CMD, U_TX, U_RX, U_CHECK);

    function first_step return step_t is
    begin
        if W25 then
            return S_W_PU;
        end if;
        return S_A_RESET;
    end function;

    function next_step(s : step_t) return step_t is
    begin
        case s is
            when S_W_PU      => return S_W_RSTEN;
            when S_W_RSTEN   => return S_W_RST;
            when S_W_RST     => return S_W_RSTWAIT;
            when S_W_RSTWAIT => return S_W_ID;
            when S_W_ID      => return S_W_SR1;
            when S_W_SR1     => return S_W_SR2;
            when S_W_SR2     => return S_W_SR3;
            when S_W_SR3     => return S_QREAD;
            when S_A_RESET   => return S_A_PU;
            when S_A_PU      => return S_A_ID;
            when S_A_ID      => return S_A_WREN1;
            when S_A_WREN1   => return S_A_CR2W;
            when S_A_CR2W    => return S_A_WREN2;
            when S_A_WREN2   => return S_A_SRW;
            when S_A_SRW     => return S_A_CR2R;
            when S_A_CR2R    => return S_A_CR1R;
            when S_A_CR1R    => return S_A_SRR;
            when S_A_SRR     => return S_QREAD;
            when S_QREAD     => return S_DONE;
            when others      => return s;
        end case;
    end function;

    -- Wait steps (no command)
    function is_wait(s : step_t) return boolean is
    begin
        return s = S_W_PU or s = S_W_RSTWAIT or s = S_A_RESET or s = S_A_PU;
    end function;

    type buf_t is array (0 to 7) of std_logic_vector(7 downto 0);

    signal cur      : step_t := S_IDLE;
    signal sub      : sub_t := U_WAIT;
    signal count    : natural range 0 to 2 ** 26 - 1 := 0;
    signal buf      : buf_t := (others => (others => '0'));
    signal n_rx     : natural range 0 to 8 := 0;
    signal n_tx     : natural range 0 to 2 := 0;
    signal done_r   : std_logic := '0';
    signal err_r    : std_logic := '0';
    signal code_r   : std_logic_vector(1 downto 0) := ERR_NONE;
    signal rst_mem  : std_logic := '1';
    signal valid_r  : std_logic := '0';
    signal tx_val_r : std_logic := '0';
    signal tx_dat_r : std_logic_vector(7 downto 0) := (others => '0');
begin
    init_done   <= done_r;
    init_err    <= err_r;
    err_code    <= code_r;
    step        <= std_logic_vector(to_unsigned(step_t'pos(cur), 5));
    mem_reset_n <= rst_mem;
    cmd_valid   <= valid_r;
    tx_tvalid   <= tx_val_r;
    tx_tdata    <= tx_dat_r;
    rx_tready   <= '1';

    process (clk)
        -- Command fields for a step
        procedure set_cmd(s : step_t) is
        begin
            cmd_lanes      <= L111;
            cmd_addr       <= (others => '0');
            cmd_addr_bytes <= 0;
            cmd_mode_en    <= '0';
            cmd_mode       <= x"FF";
            cmd_latency    <= 0;
            cmd_dir        <= DIR_NONE;
            cmd_len        <= to_unsigned(1, 16);
            cmd_sclk_div   <= SCLK_DIV;
            cmd_write      <= '0';
            case s is
                when S_W_RSTEN =>
                    cmd_op <= OP_W25_RSTEN;
                when S_W_RST =>
                    cmd_op <= OP_W25_RST;
                when S_W_ID | S_A_ID =>
                    cmd_op       <= OP_RDID;
                    cmd_dir      <= DIR_RX;
                    cmd_len      <= to_unsigned(P.id_bytes, 16);
                    cmd_sclk_div <= SLOW_DIV;
                when S_W_SR1 | S_A_SRR =>
                    cmd_op       <= OP_RDSR;
                    cmd_dir      <= DIR_RX;
                    cmd_sclk_div <= SLOW_DIV;
                when S_W_SR2 =>
                    cmd_op  <= OP_W25_RDSR2;
                    cmd_dir <= DIR_RX;
                when S_W_SR3 =>
                    cmd_op  <= OP_W25_RDSR3;
                    cmd_dir <= DIR_RX;
                when S_A_WREN1 | S_A_WREN2 =>
                    cmd_op <= OP_WREN;
                when S_A_CR2W =>
                    cmd_op         <= OP_AS_WRAR;
                    cmd_addr       <= std_logic_vector(to_unsigned(AS_REG_CR2, 32));
                    cmd_addr_bytes <= 4;
                    cmd_dir        <= DIR_TX;
                    cmd_write      <= '1';
                when S_A_SRW =>
                    cmd_op    <= OP_AS_WRSR;
                    cmd_dir   <= DIR_TX;
                    cmd_write <= '1';
                when S_A_CR2R | S_A_CR1R =>
                    cmd_op <= OP_AS_RDAR;
                    if s = S_A_CR2R then
                        cmd_addr <= std_logic_vector(to_unsigned(AS_REG_CR2, 32));
                    else
                        cmd_addr <= std_logic_vector(to_unsigned(AS_REG_CR1, 32));
                    end if;
                    cmd_addr_bytes <= 4;
                    cmd_latency    <= AS_CR2_MLATS;
                    cmd_dir        <= DIR_RX;
                when others =>                                       -- S_QREAD
                    cmd_op         <= OP_READ_QIO;
                    cmd_lanes      <= L144;
                    cmd_addr_bytes <= P.addr_bytes;
                    cmd_mode_en    <= '1';
                    cmd_mode       <= MODE_BYTE_NO_XIP;
                    cmd_latency    <= P.read_dummy;
                    cmd_dir        <= DIR_RX;
                    cmd_len        <= to_unsigned(8, 16);
            end case;
        end procedure;

        -- Byte d of the RX buffer for die k (1-line data: die 1, die 2 per byte)
        impure function rxb(d : natural; k : natural) return std_logic_vector is
        begin
            return buf(DIES * d + k);
        end function;

        -- Check the received bytes of step s; true = ok
        impure function check_ok(s : step_t) return boolean is
            variable ok : boolean := true;
            variable id : std_logic_vector(31 downto 0);
            variable b  : std_logic_vector(7 downto 0);
        begin
            for k in 0 to DIES - 1 loop
                b := rxb(0, k);
                case s is
                    when S_W_ID | S_A_ID =>
                        id := rxb(0, k) & rxb(1, k) & rxb(2, k) & rxb(3, k);
                        ok := ok and id_ok(DEVICE, id);
                    when S_W_SR1 =>
                        ok := ok and (b and W25_SR1_PROTECT) = x"00";
                    when S_W_SR2 =>
                        ok := ok and b(W25_SR2_CMP) = '0' and b(W25_SR2_QE) = '1';
                    when S_W_SR3 =>
                        ok := ok and b(W25_SR3_WPS) = '0';
                    when S_A_CR2R =>
                        ok := ok and to_integer(unsigned(b(3 downto 0))) = AS_CR2_MLATS;
                    when S_A_CR1R =>
                        ok := ok and b(1 downto 0) = "00";
                    when S_A_SRR =>
                        ok := ok and (b and AS_SR_PROTECT) = x"00";
                    when others =>
                        null;
                end case;
            end loop;
            return ok;
        end function;

        procedure enter(s : step_t) is
        begin
            cur   <= s;
            sub   <= U_WAIT;
            n_rx  <= 0;
            count <= 0;
            case s is
                when S_W_PU | S_A_PU =>
                    count   <= N_POWERUP;
                    rst_mem <= '1';
                when S_W_RSTWAIT =>
                    count <= N_RESET;
                when S_A_RESET =>
                    count   <= N_RESET;
                    rst_mem <= '0';
                when S_DONE =>
                    done_r <= '1';
                when others =>
                    null;
            end case;
        end procedure;
    begin
        if rising_edge(clk) then
            case cur is
                when S_IDLE =>
                    done_r <= '0';
                    err_r  <= '0';
                    code_r <= ERR_NONE;
                    enter(first_step);

                when S_DONE | S_ERROR =>
                    if init_restart = '1' then
                        cur <= S_IDLE;
                    end if;

                when others =>
                    case sub is
                        when U_WAIT =>
                            -- Commands start, and wait times count, once qspi_xact is idle
                            -- (so tRST/tPU are measured from CS# high / RESET# edge)
                            if xact_busy = '0' then
                                if count /= 0 then
                                    count <= count - 1;
                                elsif is_wait(cur) then
                                    enter(next_step(cur));
                                else
                                    set_cmd(cur);
                                    valid_r <= '1';
                                    sub     <= U_CMD;
                                end if;
                            end if;

                        when U_CMD =>
                            if cmd_ready = '1' then
                                valid_r <= '0';
                                case cur is
                                    when S_A_CR2W | S_A_SRW =>
                                        if cur = S_A_CR2W then
                                            tx_dat_r <= std_logic_vector(to_unsigned(AS_CR2_MLATS, 8));
                                        else
                                            tx_dat_r <= x"00";
                                        end if;
                                        tx_val_r <= '1';
                                        n_tx     <= DIES;
                                        sub      <= U_TX;
                                    when S_W_RSTEN | S_W_RST | S_A_WREN1 | S_A_WREN2 =>
                                        enter(next_step(cur));
                                    when others =>
                                        sub <= U_RX;
                                end case;
                            end if;

                        when U_TX =>
                            if tx_tready = '1' then
                                if n_tx = 1 then
                                    tx_val_r <= '0';
                                    enter(next_step(cur));
                                end if;
                                n_tx <= n_tx - 1;
                            end if;

                        when U_RX =>
                            if rx_tvalid = '1' then
                                if n_rx < 8 then
                                    buf(n_rx) <= rx_tdata;
                                    n_rx      <= n_rx + 1;
                                end if;
                                if rx_tlast = '1' then
                                    sub <= U_CHECK;
                                end if;
                            end if;

                        when U_CHECK =>
                            if cur = S_QREAD or check_ok(cur) then
                                enter(next_step(cur));
                            else
                                err_r <= '1';
                                if cur = S_W_ID or cur = S_A_ID then
                                    code_r <= ERR_ID;
                                else
                                    code_r <= ERR_CFG;
                                end if;
                                cur <= S_ERROR;
                            end if;
                    end case;
            end case;

            if reset_n = '0' then
                cur      <= S_IDLE;
                sub      <= U_WAIT;
                valid_r  <= '0';
                tx_val_r <= '0';
                rst_mem  <= '1';
                done_r   <= '0';
                err_r    <= '0';
                code_r   <= ERR_NONE;
            end if;
        end if;
    end process;
end architecture rtl;
