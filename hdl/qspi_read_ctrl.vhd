-- QSPI read front end: read requests -> EBh commands for qspi_xact, with credit-based flow control
--
--   s_axis_req (tdata = {len[15:0], addr[31:0]}, host bytes) --> cmd_* (EBh, 1-4-4) --> qspi_xact
--   rx_* (from qspi_xact)                                    --> m_axis (passed through)
--
--   Host bytes: one per SCLK cycle, {die2_nibble, die1_nibble}; host address / 2 = die byte
--   address. A request needs an even address and an even, non-zero length, init_done = '1', and
--   addr + len <= 2 * die size (no wrap). Otherwise it is dropped and req_err pulses for one cycle.
--
--   Flow control: the PHY can't stop SCLK, so a request only starts when the downstream buffer
--   has room for all of it: rx_space (free bytes downstream) >= in_flight + len, where in_flight
--   counts the bytes of started requests that haven't left m_axis yet. m_axis_tready must then
--   stay high as long as rx_space promised (it's just passed to qspi_xact).
--   One request is buffered while the previous one runs; qspi_xact starts the next EBh as soon as
--   the last byte of the previous one is in.
--   Latency and address bytes come from DEVICE (W25Q128JV: 3 address bytes + 4 dummy clocks;
--   AS308G208: 4 address bytes + MLATS = 8, as set by qspi_init).

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.qspi_pkg.all;

entity qspi_read_ctrl is
    generic (
        DEVICE   : device_t := DEV_W25Q128JV;
        SCLK_DIV : positive := 1;                   -- SCLK = input clock / (2 * SCLK_DIV)
        SPACE_W  : positive := 16                   -- Width of rx_space
    );
    port (
        clk               : in  std_logic;
        reset_n           : in  std_logic;          -- Synchronous, active low
        init_done         : in  std_logic;

        -- Read requests
        s_axis_req_tdata  : in  std_logic_vector(47 downto 0);   -- {len[15:0], addr[31:0]}
        s_axis_req_tvalid : in  std_logic;
        s_axis_req_tready : out std_logic;
        req_err           : out std_logic;          -- One-cycle pulse: request dropped
        rx_space          : in  unsigned(SPACE_W - 1 downto 0);  -- Free bytes downstream
        busy              : out std_logic;          -- Request pending or data in flight

        -- Command port to qspi_xact
        cmd_valid         : out std_logic;
        cmd_ready         : in  std_logic;
        cmd_op            : out std_logic_vector(7 downto 0);
        cmd_lanes         : out cmd_lanes_t;
        cmd_addr          : out std_logic_vector(31 downto 0);
        cmd_addr_bytes    : out natural range 0 to 4;
        cmd_mode_en       : out std_logic;
        cmd_mode          : out std_logic_vector(7 downto 0);
        cmd_latency       : out natural range 0 to 15;
        cmd_dir           : out dir_t;
        cmd_len           : out unsigned(15 downto 0);
        cmd_sclk_div      : out natural range 1 to SCLK_DIV_MAX;
        cmd_write         : out std_logic;

        -- RX data from qspi_xact, and out
        rx_tdata          : in  std_logic_vector(7 downto 0);
        rx_tvalid         : in  std_logic;
        rx_tready         : out std_logic;
        rx_tlast          : in  std_logic;
        m_axis_tdata      : out std_logic_vector(7 downto 0);
        m_axis_tvalid     : out std_logic;
        m_axis_tready     : in  std_logic;
        m_axis_tlast      : out std_logic
    );
end entity qspi_read_ctrl;

architecture rtl of qspi_read_ctrl is

    constant P         : dev_params_t := dev_params(DEVICE);
    constant HOST_SIZE : unsigned(32 downto 0) := shift_left(to_unsigned(P.size_bytes, 33), 1);

    signal pend_valid : std_logic := '0';
    signal pend_addr  : unsigned(31 downto 0) := (others => '0');
    signal pend_len   : unsigned(15 downto 0) := (others => '0');
    signal cmd_v      : std_logic := '0';
    signal in_flight  : unsigned(SPACE_W downto 0) := (others => '0');
    signal err_r      : std_logic := '0';
    signal req_ready  : std_logic;
    signal beat       : std_logic;
begin
    req_ready         <= not pend_valid;
    s_axis_req_tready <= req_ready;
    req_err           <= err_r;
    cmd_valid         <= cmd_v;
    busy              <= '1' when pend_valid = '1' or cmd_v = '1' or in_flight /= 0 else '0';

    -- Fixed command fields: EBh, 1-4-4, mode byte Fxh, device latency
    cmd_op         <= OP_READ_QIO;
    cmd_lanes      <= L144;
    cmd_addr_bytes <= P.addr_bytes;
    cmd_mode_en    <= '1';
    cmd_mode       <= MODE_BYTE_NO_XIP;
    cmd_latency    <= P.read_dummy;
    cmd_dir        <= DIR_RX;
    cmd_sclk_div   <= SCLK_DIV;
    cmd_write      <= '0';

    -- RX data passes straight through
    m_axis_tdata  <= rx_tdata;
    m_axis_tvalid <= rx_tvalid;
    m_axis_tlast  <= rx_tlast;
    rx_tready     <= m_axis_tready;
    beat          <= rx_tvalid and m_axis_tready;

    process (clk)
        variable addr  : unsigned(31 downto 0);
        variable len   : unsigned(15 downto 0);
        variable issue : boolean;
        variable fl    : unsigned(SPACE_W downto 0);
    begin
        if rising_edge(clk) then
            err_r <= '0';

            -- Accept and check a request
            if req_ready = '1' and s_axis_req_tvalid = '1' then
                addr := unsigned(s_axis_req_tdata(31 downto 0));
                len  := unsigned(s_axis_req_tdata(47 downto 32));
                if init_done = '0' or addr(0) = '1' or len(0) = '1' or len = 0
                   or resize(addr, 33) + len > HOST_SIZE then
                    err_r <= '1';
                else
                    pend_valid <= '1';
                    pend_addr  <= addr;
                    pend_len   <= len;
                end if;
            end if;

            -- Start the pending request when the command port is free and the data fits
            issue := pend_valid = '1' and cmd_v = '0'
                     and resize(rx_space, SPACE_W + 1) >= in_flight + pend_len;
            if issue then
                cmd_v      <= '1';
                cmd_addr   <= std_logic_vector(shift_right(pend_addr, 1));
                cmd_len    <= pend_len;
                pend_valid <= '0';
            elsif cmd_v = '1' and cmd_ready = '1' then
                cmd_v <= '0';
            end if;

            fl := in_flight;
            if issue then
                fl := fl + pend_len;
            end if;
            if beat = '1' then
                fl := fl - 1;
            end if;
            in_flight <= fl;

            if reset_n = '0' then
                pend_valid <= '0';
                cmd_v      <= '0';
                in_flight  <= (others => '0');
                err_r      <= '0';
            end if;
        end if;
    end process;
end architecture rtl;
