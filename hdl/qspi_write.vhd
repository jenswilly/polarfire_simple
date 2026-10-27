-- QSPI write path (test patterns and calibration): write requests -> commands for qspi_xact
--
--   s_axis_req (tdata = {len[15:0], addr[31:0]}, host bytes) + s_axis_data (len host bytes)
--     --> cmd_* / tx_* --> qspi_xact
--
--   Same request format and checks as qspi_read_ctrl: even address, even non-zero length,
--   init_done = '1', addr + len <= 2 * die size; otherwise req_err pulses and the request is
--   dropped (its data is not consumed). Data bytes are host bytes {die2_nibble, die1_nibble};
--   with one die the upper nibble is ignored. The die address is addr / 2.
--
--   W25Q128JV: every 4 KB sector touched by the request is erased first (WREN + 20h, then 05h
--     polling until BUSY = 0), so other data in those sectors is lost. Then the data is
--     programmed page by page (WREN + 32h 1-1-4, split at 256-byte page boundaries), polling
--     BUSY after each page.
--   AS308G208: WREN + one D2h (1-4-4, mode byte Fxh) for the whole request. Done once
--     qspi_xact is idle again, i.e. after the 600 ns CS# high write time.
--   wr_done pulses for one cycle when the request has been written completely.

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.qspi_pkg.all;

entity qspi_write is
    generic (
        DEVICE       : device_t := DEV_W25Q128JV;
        DIE2_PRESENT : boolean  := false;
        SCLK_DIV     : positive := 2                -- SCLK = input clock / (2 * SCLK_DIV)
    );
    port (
        clk                : in  std_logic;
        reset_n            : in  std_logic;         -- Synchronous, active low
        init_done          : in  std_logic;

        -- Write requests and their data
        s_axis_req_tdata   : in  std_logic_vector(47 downto 0);   -- {len[15:0], addr[31:0]}
        s_axis_req_tvalid  : in  std_logic;
        s_axis_req_tready  : out std_logic;
        s_axis_data_tdata  : in  std_logic_vector(7 downto 0);
        s_axis_data_tvalid : in  std_logic;
        s_axis_data_tready : out std_logic;
        req_err            : out std_logic;         -- One-cycle pulse: request dropped
        wr_done            : out std_logic;         -- One-cycle pulse: request written
        busy               : out std_logic;

        -- Command port to qspi_xact
        cmd_valid          : out std_logic;
        cmd_ready          : in  std_logic;
        cmd_op             : out std_logic_vector(7 downto 0);
        cmd_lanes          : out cmd_lanes_t;
        cmd_addr           : out std_logic_vector(31 downto 0);
        cmd_addr_bytes     : out natural range 0 to 4;
        cmd_mode_en        : out std_logic;
        cmd_mode           : out std_logic_vector(7 downto 0);
        cmd_latency        : out natural range 0 to 15;
        cmd_dir            : out dir_t;
        cmd_len            : out unsigned(15 downto 0);
        cmd_sclk_div       : out natural range 1 to SCLK_DIV_MAX;
        cmd_write          : out std_logic;
        xact_busy          : in  std_logic;

        tx_tdata           : out std_logic_vector(7 downto 0);
        tx_tvalid          : out std_logic;
        tx_tready          : in  std_logic;

        rx_tdata           : in  std_logic_vector(7 downto 0);
        rx_tvalid          : in  std_logic;
        rx_tready          : out std_logic;
        rx_tlast           : in  std_logic
    );
end entity qspi_write;

architecture rtl of qspi_write is

    constant P         : dev_params_t := dev_params(DEVICE);
    constant W25       : boolean := DEVICE = DEV_W25Q128JV;
    constant HOST_SIZE : unsigned(32 downto 0) := shift_left(to_unsigned(P.size_bytes, 33), 1);
    constant SECTOR    : positive := 4096;

    type state_t is (W_IDLE,
                     W_ERASE_WREN, W_ERASE, W_PROG_WREN, W_PROG, W_POLL, W_POLL_RX,   -- W25Q
                     W_AS_WREN, W_AS_WRITE, W_AS_WAIT,                               -- AS
                     W_DONE);

    signal state     : state_t := W_IDLE;
    signal next_st   : state_t := W_IDLE;              -- State after the BUSY poll
    signal cmd_v     : std_logic := '0';
    signal die_addr  : unsigned(31 downto 0) := (others => '0');   -- Next byte to program
    signal die_left  : unsigned(15 downto 0) := (others => '0');   -- Bytes still to program
    signal chunk     : unsigned(15 downto 0) := (others => '0');   -- Bytes in the current page
    signal sec_addr  : unsigned(31 downto 0) := (others => '0');   -- Next sector to erase
    signal sec_last  : unsigned(31 downto 0) := (others => '0');
    signal host_len  : unsigned(15 downto 0) := (others => '0');
    signal poll_busy : std_logic := '0';
    signal err_r     : std_logic := '0';
    signal done_r    : std_logic := '0';
    signal req_ready : std_logic;
begin
    req_ready          <= '1' when state = W_IDLE else '0';
    s_axis_req_tready  <= req_ready;
    req_err            <= err_r;
    wr_done            <= done_r;
    busy               <= '0' when state = W_IDLE else '1';
    cmd_valid          <= cmd_v;
    rx_tready          <= '1';

    -- Data goes straight to qspi_xact, which takes exactly cmd_len bytes per program/write command
    tx_tdata           <= s_axis_data_tdata;
    tx_tvalid          <= s_axis_data_tvalid when state = W_PROG or state = W_AS_WRITE or
                                                  state = W_POLL or state = W_AS_WAIT else '0';
    s_axis_data_tready <= tx_tready when state = W_PROG or state = W_AS_WRITE or
                                         state = W_POLL or state = W_AS_WAIT else '0';

    process (clk)
        variable addr, last : unsigned(31 downto 0);
        variable len        : unsigned(15 downto 0);
        variable room       : unsigned(15 downto 0);

        -- Issue a command (fields fixed until cmd_ready)
        procedure issue(op : std_logic_vector(7 downto 0); lanes : cmd_lanes_t;
                        a : unsigned(31 downto 0); ab : natural; mode_en : std_logic;
                        dir : dir_t; n : unsigned(15 downto 0); wr : std_logic;
                        div : positive) is
        begin
            cmd_v          <= '1';
            cmd_op         <= op;
            cmd_lanes      <= lanes;
            cmd_addr       <= std_logic_vector(a);
            cmd_addr_bytes <= ab;
            cmd_mode_en    <= mode_en;
            cmd_mode       <= MODE_BYTE_NO_XIP;
            cmd_latency    <= 0;
            cmd_dir        <= dir;
            cmd_len        <= n;
            cmd_write      <= wr;
            cmd_sclk_div   <= div;
        end procedure;

        -- WREN counts as a write for the CS# high time (W25Q tSHSL2 50 ns): with 10 ns the
        -- W25Q128JV kept WEL but ignored the following 20h/32h (seen on hardware)
        procedure issue_wren is
        begin
            issue(OP_WREN, L111, (others => '0'), 0, '0', DIR_NONE, to_unsigned(1, 16), '1', SCLK_DIV);
        end procedure;

        procedure issue_poll is
        begin
            issue(OP_RDSR, L111, (others => '0'), 0, '0', DIR_RX, to_unsigned(1, 16), '0', SCLK_DIV);
        end procedure;

        -- Bytes that fit in the page of die address a (256 - a mod 256), at most n
        function page_chunk(a : unsigned(31 downto 0); n : unsigned(15 downto 0)) return unsigned is
            variable r : unsigned(15 downto 0);
        begin
            r := to_unsigned(256, 16) - resize(a(7 downto 0), 16);
            if n < r then
                return n;
            end if;
            return r;
        end function;
    begin
        if rising_edge(clk) then
            err_r  <= '0';
            done_r <= '0';
            if cmd_v = '1' and cmd_ready = '1' then
                cmd_v <= '0';
            end if;

            case state is
                when W_IDLE =>
                    if s_axis_req_tvalid = '1' then
                        addr := unsigned(s_axis_req_tdata(31 downto 0));
                        len  := unsigned(s_axis_req_tdata(47 downto 32));
                        if init_done = '0' or addr(0) = '1' or len(0) = '1' or len = 0
                           or resize(addr, 33) + len > HOST_SIZE then
                            err_r <= '1';
                        else
                            die_addr <= shift_right(addr, 1);
                            die_left <= shift_right(len, 1);
                            host_len <= len;
                            if W25 then
                                last     := shift_right(addr, 1) + shift_right(len, 1) - 1;
                                sec_addr <= shift_right(addr, 1) and not to_unsigned(SECTOR - 1, 32);
                                sec_last <= last and not to_unsigned(SECTOR - 1, 32);
                                issue_wren;
                                state <= W_ERASE_WREN;
                            else
                                issue_wren;
                                state <= W_AS_WREN;
                            end if;
                        end if;
                    end if;

                -- W25Q128JV ------------------------------------------------------------------
                when W_ERASE_WREN =>
                    if cmd_v = '1' and cmd_ready = '1' then
                        issue(OP_W25_SE, L111, sec_addr, P.addr_bytes, '0', DIR_NONE,
                              to_unsigned(1, 16), '1', SCLK_DIV);
                        state <= W_ERASE;
                    end if;

                when W_ERASE =>
                    if cmd_v = '1' and cmd_ready = '1' then
                        issue_poll;
                        if sec_addr = sec_last then
                            next_st <= W_PROG_WREN;
                        else
                            next_st <= W_ERASE_WREN;
                        end if;
                        sec_addr <= sec_addr + SECTOR;
                        state <= W_POLL;
                    end if;

                when W_PROG_WREN =>
                    if cmd_v = '1' and cmd_ready = '1' then
                        room := page_chunk(die_addr, die_left);
                        chunk <= room;
                        issue(OP_W25_QPP, L114, die_addr, P.addr_bytes, '0', DIR_TX,
                              shift_left(room, 1), '1', SCLK_DIV);
                        state <= W_PROG;
                    end if;

                when W_PROG =>
                    if cmd_v = '1' and cmd_ready = '1' then
                        issue_poll;
                        die_addr <= die_addr + chunk;
                        die_left <= die_left - chunk;
                        if die_left = chunk then
                            next_st <= W_DONE;
                        else
                            next_st <= W_PROG_WREN;
                        end if;
                        state <= W_POLL;
                    end if;

                when W_POLL =>
                    if cmd_v = '1' and cmd_ready = '1' then
                        poll_busy <= '0';
                        state     <= W_POLL_RX;
                    end if;

                when W_POLL_RX =>
                    if rx_tvalid = '1' then
                        if rx_tdata(W25_SR1_BUSY) = '1' then
                            poll_busy <= '1';
                        end if;
                        if rx_tlast = '1' then
                            if poll_busy = '1' or rx_tdata(W25_SR1_BUSY) = '1' then
                                issue_poll;
                                state <= W_POLL;
                            elsif next_st = W_DONE then
                                state <= W_DONE;
                            else
                                issue_wren;
                                state <= next_st;
                            end if;
                        end if;
                    end if;

                -- AS308G208 ------------------------------------------------------------------
                when W_AS_WREN =>
                    if cmd_v = '1' and cmd_ready = '1' then
                        issue(OP_AS_WRQIO, L144, die_addr, P.addr_bytes, '1', DIR_TX, host_len,
                              '1', SCLK_DIV);
                        state <= W_AS_WRITE;
                    end if;

                when W_AS_WRITE =>
                    if cmd_v = '1' and cmd_ready = '1' then
                        state <= W_AS_WAIT;
                    end if;

                when W_AS_WAIT =>
                    -- qspi_xact busy covers the data, CS# high and the write CS# high time
                    if xact_busy = '0' then
                        state <= W_DONE;
                    end if;

                when W_DONE =>
                    done_r <= '1';
                    state  <= W_IDLE;
            end case;

            if reset_n = '0' then
                state <= W_IDLE;
                cmd_v <= '0';
                err_r <= '0';
            end if;
        end if;
    end process;
end architecture rtl;
