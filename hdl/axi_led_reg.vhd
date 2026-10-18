-- Minimal AXI4-Lite slave: two LED bits, read-only ID register and a debug pulse
--   offset 0x0: LED control  (R/W)  bit0 = LED2, bit1 = LED3
--   offset 0x4: ID           (RO)   0x1ED50001
--   offset 0x8: DEBUG        (WO)   write bit0 = 1 -> DEBUG_PULSE high for one ACLK cycle (reads 0)

library ieee;
use ieee.std_logic_1164.all;

entity axi_led_reg is
    generic (
        ADDR_WIDTH : integer := 38
    );
    port (
        ACLK    : in  std_logic;
        ARESETN : in  std_logic;
        -- write address channel
        AWADDR  : in  std_logic_vector(ADDR_WIDTH-1 downto 0);
        AWPROT  : in  std_logic_vector(2 downto 0);
        AWVALID : in  std_logic;
        AWREADY : out std_logic;
        -- write data channel
        WDATA   : in  std_logic_vector(31 downto 0);
        WSTRB   : in  std_logic_vector(3 downto 0);
        WVALID  : in  std_logic;
        WREADY  : out std_logic;
        -- write response channel
        BRESP   : out std_logic_vector(1 downto 0);
        BVALID  : out std_logic;
        BREADY  : in  std_logic;
        -- read address channel
        ARADDR  : in  std_logic_vector(ADDR_WIDTH-1 downto 0);
        ARPROT  : in  std_logic_vector(2 downto 0);
        ARVALID : in  std_logic;
        ARREADY : out std_logic;
        -- read data channel
        RDATA   : out std_logic_vector(31 downto 0);
        RRESP   : out std_logic_vector(1 downto 0);
        RVALID  : out std_logic;
        RREADY  : in  std_logic;

        -- LEDs
        LED2    : out std_logic;
        LED3    : out std_logic;

        -- Debug pulse (one ACLK cycle per write to 0x8)
        DEBUG_PULSE : out std_logic
    );
end entity axi_led_reg;

architecture rtl of axi_led_reg is
    constant ID_VALUE : std_logic_vector(31 downto 0) := x"1ED50001";

    signal led_reg  : std_logic_vector(1 downto 0);
    signal pulse_i  : std_logic;
    signal wr_ready : std_logic;
    signal bvalid_i : std_logic;
    signal rd_ready : std_logic;
    signal rvalid_i : std_logic;
    signal rdata_i  : std_logic_vector(31 downto 0);
begin
    -- Accept a write when address and data are both present and no response is pending
    wr_ready <= AWVALID and WVALID and not bvalid_i;
    AWREADY  <= wr_ready;
    WREADY   <= wr_ready;
    BVALID   <= bvalid_i;
    BRESP    <= "00";

    -- Accept a read when no read data is pending
    rd_ready <= ARVALID and not rvalid_i;
    ARREADY  <= rd_ready;
    RVALID   <= rvalid_i;
    RDATA    <= rdata_i;
    RRESP    <= "00";

    write_proc : process (ACLK)
    begin
        if rising_edge(ACLK) then
            -- Default: the pulse lasts only the cycle after the accepted write
            pulse_i <= '0';
            if ARESETN = '0' then
                led_reg  <= (others => '0');
                bvalid_i <= '0';
            elsif wr_ready = '1' then
                bvalid_i <= '1';
                if AWADDR(3 downto 2) = "00" and WSTRB(0) = '1' then
                    led_reg <= WDATA(1 downto 0);
                end if;
                if AWADDR(3 downto 2) = "10" and WSTRB(0) = '1' then
                    pulse_i <= WDATA(0);
                end if;
            elsif BREADY = '1' then
                bvalid_i <= '0';
            end if;
        end if;
    end process;

    read_proc : process (ACLK)
    begin
        if rising_edge(ACLK) then
            if ARESETN = '0' then
                rvalid_i <= '0';
                rdata_i  <= (others => '0');
            elsif rd_ready = '1' then
                rvalid_i <= '1';
                rdata_i  <= (others => '0');
                case ARADDR(3 downto 2) is
                    when "00"   => rdata_i(1 downto 0) <= led_reg;
                    when "01"   => rdata_i <= ID_VALUE;
                    when others => null;
                end case;
            elsif RREADY = '1' then
                rvalid_i <= '0';
            end if;
        end if;
    end process;

    -- Assign signals to outputs
    LED2 <= led_reg(0);
    LED3 <= led_reg(1);
    DEBUG_PULSE <= pulse_i;
end architecture rtl;
