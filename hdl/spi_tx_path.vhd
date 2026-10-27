-- SPI TX path: 10-byte blocks in, SPI frames out
--
--   s_* (80-bit block, valid/ready) --> block_fifo --> block_serializer --> axis_spi_wo_master --> SPI
--
--   Every block becomes one SPI frame (one cs_n assertion, 10 bytes), sent MSB first, so
--   bit 79 is the first bit on MOSI. The FIFO holds 512 blocks; when it is full, s_ready
--   goes low and the producer waits. Because the serializer holds a whole block, the SPI
--   master never runs dry mid-frame. See documentation/spi_tx_path.drawio.

library ieee;
use ieee.std_logic_1164.all;

entity spi_tx_path is
    generic (
        BLOCK_BYTES : positive  := 10;     -- Must match the CoreFIFO width / 8 (checked in block_fifo)
        CLK_DIV     : positive  := 5;      -- Clk cycles per sclk half-period (20 MHz at 200 MHz)
        CPOL        : std_logic := '0';    -- Sclk idle level
        CPHA        : std_logic := '0';    -- 0: slave samples on leading edge, 1: on trailing edge
        CS_SETUP    : natural   := 1;      -- Extra half-periods cs_n low before the first edge
        CS_HOLD     : natural   := 1;      -- Half-periods after the last edge before cs_n high
        CS_IDLE     : natural   := 2       -- Min. half-periods cs_n high between frames
    );
    port (
        clk           : in  std_logic;
        reset_n       : in  std_logic;           -- Synchronous, active low

        -- Blocks in
        s_data        : in  std_logic_vector(BLOCK_BYTES * 8 - 1 downto 0);
        s_valid       : in  std_logic;
        s_ready       : out std_logic;

        -- SPI
        spi_sclk      : out std_logic;
        spi_mosi      : out std_logic;
        spi_cs_n      : out std_logic;

        -- Status
        busy_out      : out std_logic            -- SPI master busy (frame in progress or cs_n idle time)
    );
end entity spi_tx_path;

architecture rtl of spi_tx_path is

    -- block_fifo -> block_serializer
    signal fifo_data  : std_logic_vector(BLOCK_BYTES * 8 - 1 downto 0);
    signal fifo_valid : std_logic;
    signal fifo_ready : std_logic;

    -- block_serializer -> axis_spi_wo_master
    signal axis_tdata  : std_logic_vector(7 downto 0);
    signal axis_tvalid : std_logic;
    signal axis_tready : std_logic;

begin

    u_fifo : entity work.block_fifo
        generic map (BLOCK_BYTES => BLOCK_BYTES)
        port map (
            clk     => clk,
            reset_n => reset_n,
            s_data  => s_data,
            s_valid => s_valid,
            s_ready => s_ready,
            m_data  => fifo_data,
            m_valid => fifo_valid,
            m_ready => fifo_ready
        );

    u_ser : entity work.block_serializer
        generic map (BLOCK_BYTES => BLOCK_BYTES)
        port map (
            clk           => clk,
            reset_n       => reset_n,
            s_data        => fifo_data,
            s_valid       => fifo_valid,
            s_ready       => fifo_ready,
            m_axis_tdata  => axis_tdata,
            m_axis_tvalid => axis_tvalid,
            m_axis_tready => axis_tready,
            m_axis_tlast  => open
        );

    u_spi : entity work.axis_spi_wo_master
        generic map (
            FRAME_BYTES => BLOCK_BYTES,
            CLK_DIV     => CLK_DIV,
            CPOL        => CPOL,
            CPHA        => CPHA,
            MSB_FIRST   => true,                 -- Bit 79 first
            CS_SETUP    => CS_SETUP,
            CS_HOLD     => CS_HOLD,
            CS_IDLE     => CS_IDLE
        )
        port map (
            clk           => clk,
            reset_n       => reset_n,
            s_axis_tdata  => axis_tdata,
            s_axis_tvalid => axis_tvalid,
            s_axis_tready => axis_tready,
            spi_sclk      => spi_sclk,
            spi_mosi      => spi_mosi,
            spi_cs_n      => spi_cs_n,
            busy_out      => busy_out
        );

end architecture rtl;
