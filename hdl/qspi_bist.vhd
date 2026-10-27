-- Built-in self-test for qspi_mram_ctrl (fabric only, no software)
--
--   qspi_bist --(init_restart, rd_req, wr_req/data, sample_dly_ovr)--> qspi_mram_ctrl
--             <--(init_done/err, read data, wr_done, req errors)------
--
--   1. Wait for init. With CALIBRATE, a failed init is retried with sample delays
--      1..SAMPLE_DLY_MAX (init itself reads ID and registers, so a wrong delay can make it fail).
--   2. Write the pattern once: NBLK blocks of BLK_LEN host bytes at BASE_ADDR + k * BLK_STRIDE;
--      host byte i of block k = (k * 7 + i) mod 256. On the W25Q128JV each block's sectors are
--      erased first, so the pattern is written once per reset only (flash endurance).
--   3. With CALIBRATE: read all blocks once with each sample delay 1..SAMPLE_DLY_MAX, record
--      which delays return the pattern (cal_window(d)) and use the middle of the first passing run
--      (lower middle for an even width) from then on (cal_dly).
--   4. Read all blocks and compare. With LOOP_ROUNDS, again and again until reset (reads don't wear the
--      flash); without, once, then stop (B_DONE, no more QSPI traffic).
--
--   pass: on after the first complete correct read round, while no failure has occurred.
--   fail: init error (after all retries), request error, no passing sample delay, or a data
--         mismatch. Latched until reset. Both are off while init and the first round run.
--   With one die only the low nibble of each host byte is written and compared.
--   rd_space is always the maximum: the BIST takes every read byte at once.

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.qspi_pkg.all;

entity qspi_bist is
    generic (
        DIE2_PRESENT : boolean  := false;
        NBLK         : positive := 8;
        BLK_LEN      : positive := 880;             -- Host bytes per block (even)
        BLK_STRIDE   : positive := 16#4000#;        -- Host bytes between block starts (W25Q: 2 sectors)
        BASE_ADDR    : natural  := 0;               -- Host address of block 0 (even)
        CALIBRATE    : boolean  := false;
        LOOP_ROUNDS  : boolean  := false;           -- Keep reading and comparing until reset
        SPACE_W      : positive := 16
    );
    port (
        clk                  : in  std_logic;
        reset_n              : in  std_logic;       -- Synchronous, active low

        -- To / from qspi_mram_ctrl
        init_restart         : out std_logic;
        init_done            : in  std_logic;
        init_err             : in  std_logic;
        ctrl_busy            : in  std_logic;
        rd_req_tdata         : out std_logic_vector(47 downto 0);
        rd_req_tvalid        : out std_logic;
        rd_req_tready        : in  std_logic;
        rd_req_err           : in  std_logic;
        rd_space             : out unsigned(SPACE_W - 1 downto 0);
        rd_tdata             : in  std_logic_vector(7 downto 0);
        rd_tvalid            : in  std_logic;
        rd_tready            : out std_logic;
        rd_tlast             : in  std_logic;
        wr_req_tdata         : out std_logic_vector(47 downto 0);
        wr_req_tvalid        : out std_logic;
        wr_req_tready        : in  std_logic;
        wr_req_err           : in  std_logic;
        wr_done              : in  std_logic;
        wr_tdata             : out std_logic_vector(7 downto 0);
        wr_tvalid            : out std_logic;
        wr_tready            : in  std_logic;
        sample_dly_ovr_valid : out std_logic;
        sample_dly_ovr       : out natural range 1 to SAMPLE_DLY_MAX;

        -- Status
        pass                 : out std_logic;
        fail                 : out std_logic;
        cal_window           : out std_logic_vector(SAMPLE_DLY_MAX downto 1);  -- Passing delays
        cal_dly              : out natural range 1 to SAMPLE_DLY_MAX;          -- Delay in use (CALIBRATE)
        pass_count           : out unsigned(15 downto 0);                      -- Correct rounds
        state_dbg            : out std_logic_vector(3 downto 0)
    );
end entity qspi_bist;

architecture rtl of qspi_bist is

    type state_t is (B_INIT, B_INIT_RETRY, B_WREQ, B_WDATA, B_WDONE, B_CAL_SET, B_ROUND,
                     B_CAL_NEXT, B_CAL_PICK, B_LOOP, B_DONE, B_FAIL);

    -- Expected host byte i of block k
    function pattern(k, i : natural) return std_logic_vector is
        variable b : std_logic_vector(7 downto 0);
    begin
        b := std_logic_vector(to_unsigned((k * 7 + i) mod 256, 8));
        if not DIE2_PRESENT then
            b(7 downto 4) := "0000";
        end if;
        return b;
    end function;

    function req(k : natural) return std_logic_vector is
    begin
        return std_logic_vector(to_unsigned(BLK_LEN, 16))
             & std_logic_vector(to_unsigned(BASE_ADDR + k * BLK_STRIDE, 32));
    end function;

    signal state     : state_t := B_INIT;
    signal blk       : natural range 0 to NBLK := 0;           -- Write: block; read: requests sent
    signal idx       : natural range 0 to BLK_LEN := 0;        -- Write: byte within the block
    signal rx_blk    : natural range 0 to NBLK := 0;           -- Read check: block
    signal rx_idx    : natural range 0 to BLK_LEN := 0;        -- Read check: byte
    signal round_bad : std_logic := '0';                       -- Mismatch in this round
    signal try_dly   : natural range 1 to SAMPLE_DLY_MAX := 1;
    signal tries     : natural range 0 to SAMPLE_DLY_MAX := 0;
    signal window    : std_logic_vector(SAMPLE_DLY_MAX downto 1) := (others => '0');
    signal ovr_v     : std_logic := '0';
    signal ovr_d     : natural range 1 to SAMPLE_DLY_MAX := 1;
    signal restart   : std_logic := '0';
    signal pass_r    : std_logic := '0';
    signal fail_r    : std_logic := '0';
    signal count     : unsigned(15 downto 0) := (others => '0');
    signal calibrating : std_logic := '0';                     -- Current round is a calibration round
    signal wait_cnt  : natural range 0 to 3 := 0;              -- Cycles until init status is valid
    -- ctrl_busy, registered: it is combinational over several levels in qspi_mram_ctrl and failed
    -- setup at 200 MHz into this state machine. One cycle late is safe: only the BIST makes the
    -- controller busy, and it issues nothing in the states that wait for busy_r = '0'.
    signal busy_r    : std_logic := '1';
begin
    init_restart         <= restart;
    rd_space             <= (others => '1');
    rd_tready            <= '1';
    rd_req_tdata         <= req(blk);
    rd_req_tvalid        <= '1' when (state = B_ROUND) and blk < NBLK else '0';
    wr_req_tdata         <= req(blk);
    wr_req_tvalid        <= '1' when state = B_WREQ else '0';
    wr_tdata             <= pattern(blk, idx);
    wr_tvalid            <= '1' when state = B_WDATA else '0';
    sample_dly_ovr_valid <= ovr_v;
    sample_dly_ovr       <= ovr_d;
    pass                 <= pass_r and not fail_r;
    fail                 <= fail_r;
    cal_window           <= window;
    cal_dly              <= ovr_d;
    pass_count           <= count;
    state_dbg            <= std_logic_vector(to_unsigned(state_t'pos(state), 4));

    process (clk)
        variable lo, hi : natural range 0 to SAMPLE_DLY_MAX;
        variable got    : std_logic_vector(7 downto 0);
    begin
        if rising_edge(clk) then
            restart <= '0';
            busy_r  <= ctrl_busy;

            -- Read data check (runs in B_ROUND)
            if rd_tvalid = '1' then
                got := rd_tdata;
                if not DIE2_PRESENT then
                    got(7 downto 4) := "0000";
                end if;
                if rx_blk >= NBLK or got /= pattern(rx_blk, rx_idx)
                   or (rd_tlast = '1') /= (rx_idx = BLK_LEN - 1) then
                    round_bad <= '1';
                end if;
                if rd_tlast = '1' then
                    rx_idx <= 0;
                    if rx_blk < NBLK then
                        rx_blk <= rx_blk + 1;
                    end if;
                elsif rx_idx < BLK_LEN then
                    rx_idx <= rx_idx + 1;
                end if;
            end if;

            if rd_req_err = '1' or wr_req_err = '1' then
                fail_r <= '1';
                state  <= B_FAIL;
            else
                case state is
                    ---------------------------------------------------------------- Init
                    when B_INIT =>
                        if wait_cnt /= 0 then
                            wait_cnt <= wait_cnt - 1;          -- init_done/err not updated yet
                        elsif init_done = '1' then
                            blk   <= 0;
                            idx   <= 0;
                            state <= B_WREQ;
                        elsif init_err = '1' then
                            if CALIBRATE and tries < SAMPLE_DLY_MAX then
                                tries <= tries + 1;
                                state <= B_INIT_RETRY;
                            else
                                fail_r <= '1';
                                state  <= B_FAIL;
                            end if;
                        end if;

                    when B_INIT_RETRY =>
                        -- Set the next delay and restart init once the controller is idle (the
                        -- failed init's last transaction may still be finishing)
                        if busy_r = '0' then
                            ovr_v    <= '1';
                            ovr_d    <= try_dly;
                            restart  <= '1';
                            wait_cnt <= 3;
                            if try_dly < SAMPLE_DLY_MAX then
                                try_dly <= try_dly + 1;
                            end if;
                            state <= B_INIT;
                        end if;

                    ---------------------------------------------------------------- Write
                    when B_WREQ =>
                        if wr_req_tready = '1' then
                            idx   <= 0;
                            state <= B_WDATA;
                        end if;

                    when B_WDATA =>
                        if wr_tready = '1' then
                            if idx = BLK_LEN - 1 then
                                state <= B_WDONE;
                            else
                                idx <= idx + 1;
                            end if;
                        end if;

                    when B_WDONE =>
                        if wr_done = '1' then
                            if blk = NBLK - 1 then
                                blk <= 0;
                                if CALIBRATE then
                                    try_dly <= 1;
                                    state   <= B_CAL_SET;
                                else
                                    state <= B_LOOP;
                                end if;
                            else
                                blk   <= blk + 1;
                                state <= B_WREQ;
                            end if;
                        end if;

                    ---------------------------------------------------------------- Calibration
                    when B_CAL_SET =>
                        -- Change the sample delay only while the controller is idle
                        if busy_r = '0' then
                            ovr_v       <= '1';
                            ovr_d       <= try_dly;
                            blk         <= 0;
                            rx_blk      <= 0;
                            rx_idx      <= 0;
                            round_bad   <= '0';
                            calibrating <= '1';
                            state       <= B_ROUND;
                        end if;

                    when B_CAL_NEXT =>
                        window(try_dly) <= not round_bad;
                        if try_dly = SAMPLE_DLY_MAX then
                            state <= B_CAL_PICK;
                        else
                            try_dly <= try_dly + 1;
                            state   <= B_CAL_SET;
                        end if;

                    when B_CAL_PICK =>
                        -- Middle of the first run of passing delays
                        lo := 0;
                        hi := 0;
                        for d in 1 to SAMPLE_DLY_MAX loop
                            if window(d) = '1' then
                                if lo = 0 then
                                    lo := d;
                                    hi := d;
                                elsif hi = d - 1 then
                                    hi := d;
                                end if;
                            end if;
                        end loop;
                        if lo = 0 then
                            fail_r <= '1';
                            state  <= B_FAIL;
                        elsif busy_r = '0' then
                            ovr_v       <= '1';
                            ovr_d       <= (lo + hi) / 2;
                            calibrating <= '0';
                            state       <= B_LOOP;
                        end if;

                    ---------------------------------------------------------------- Read rounds
                    when B_LOOP =>
                        blk       <= 0;
                        rx_blk    <= 0;
                        rx_idx    <= 0;
                        round_bad <= '0';
                        state     <= B_ROUND;

                    when B_ROUND =>
                        if blk < NBLK and rd_req_tready = '1' then
                            blk <= blk + 1;
                        end if;
                        -- Round complete: the last block's last byte came in in an earlier cycle,
                        -- so round_bad includes it
                        if rx_blk = NBLK then
                            if calibrating = '1' then
                                state <= B_CAL_NEXT;
                            elsif round_bad = '1' then
                                fail_r <= '1';
                                state  <= B_FAIL;
                            else
                                pass_r <= '1';
                                if count /= x"FFFF" then
                                    count <= count + 1;
                                end if;
                                if LOOP_ROUNDS then
                                    state <= B_LOOP;
                                else
                                    state <= B_DONE;
                                end if;
                            end if;
                        end if;

                    when B_DONE | B_FAIL =>
                        null;
                end case;
            end if;

            if reset_n = '0' then
                state     <= B_INIT;
                restart   <= '0';
                pass_r    <= '0';
                fail_r    <= '0';
                count     <= (others => '0');
                ovr_v     <= '0';
                tries     <= 0;
                try_dly   <= 1;
                window    <= (others => '0');
                rx_blk    <= 0;
                rx_idx    <= 0;
                round_bad <= '0';
                calibrating <= '0';
                wait_cnt  <= 0;
                busy_r    <= '1';
            end if;
        end if;
    end process;
end architecture rtl;
