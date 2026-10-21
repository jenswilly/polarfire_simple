-- QSPI memory controller: shared types, device facts and helper functions
--   Two devices are supported, selected with a DEVICE generic of type device_t:
--     DEV_W25Q128JV  Winbond W25Q128JVSSIQ, single Quad-SPI NOR flash (prototype)
--     DEV_AS308G208  Avalanche AS308G208, Dual-Quad SPI MRAM, values per CS# (final)
--   Every value comes from documentation/device_facts.md, which has the datasheet references
--   ([W] = W25Q128JV rev F, [A] = ASxxxx208 rev J.1). Change both together.
--   Reads use EBh (1-4-4) on both devices: opcode on IO0, address/mode/latency/data on IO[3:0],
--   high nibble first. See PLAN.md.
--   Generic helpers (clog2, ns_to_cycles) are in util_pkg.

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

package qspi_pkg is

    subtype byte_t is std_logic_vector(7 downto 0);

    -- Device and bus types
    type device_t    is (DEV_W25Q128JV, DEV_AS308G208);
    type lane_mode_t is (SPI1, QUAD4);                   -- 1 IO line (IO0 out, IO1 in) or 4 IO lines
    type dir_t       is (DIR_NONE, DIR_TX, DIR_RX);      -- NONE = dummy/latency clocks, IO not driven

    -- Opcodes used on both devices ([W] p.22-23, [A] Table 34)
    constant OP_WREN     : byte_t := x"06";   -- Write Enable
    constant OP_RDSR     : byte_t := x"05";   -- Read Status Register (-1 on the W25Q)
    constant OP_RDID     : byte_t := x"9F";   -- Read JEDEC / device ID
    constant OP_READ_QIO : byte_t := x"EB";   -- Fast Read Quad I/O, 1-4-4

    -- W25Q128JV only ([W] p.22-23)
    constant OP_W25_RDSR2 : byte_t := x"35";  -- Read Status Register-2
    constant OP_W25_RDSR3 : byte_t := x"15";  -- Read Status Register-3
    constant OP_W25_RSTEN : byte_t := x"66";  -- Enable Reset
    constant OP_W25_RST   : byte_t := x"99";  -- Reset Device (directly after RSTEN)
    constant OP_W25_SE    : byte_t := x"20";  -- Sector Erase 4 KB, 1-1-0
    constant OP_W25_QPP   : byte_t := x"32";  -- Quad Input Page Program, 1-1-4, max 256 B per page

    -- AS308G208 only ([A] Table 34). No software reset: use the RESET# pin.
    constant OP_AS_RDFSR : byte_t := x"70";   -- Read Flag Status Register
    constant OP_AS_RDAR  : byte_t := x"65";   -- Read Any Register, 1-1-1, 4 address bytes + latency
    constant OP_AS_WRAR  : byte_t := x"71";   -- Write Any Register, 1-1-1, 4 address bytes
    constant OP_AS_WRSR  : byte_t := x"01";   -- Write Status Register
    constant OP_AS_WRQIO : byte_t := x"D2";   -- Write Quad I/O, 1-4-4, XIP byte then data

    -- Mode byte after the EBh address: W25Q "M7-0 = Fxh", AS "XIP byte Fxh = XIP off"
    constant MODE_BYTE_NO_XIP : byte_t := x"FF";

    -- W25Q128JV status register bits ([W] p.13, 16, 17)
    constant W25_SR1_BUSY    : natural := 0;
    constant W25_SR1_WEL     : natural := 1;
    constant W25_SR1_PROTECT : byte_t  := "01111100";   -- SEC, TB, BP2-0: all 0 = nothing protected
    constant W25_SR2_QE      : natural := 1;            -- S9; fixed 1 on the -IQ part
    constant W25_SR2_CMP     : natural := 6;            -- S14
    constant W25_SR3_WPS     : natural := 2;            -- S18

    -- AS308G208 register addresses for RDAR/WRAR ([A] Table 13) and fields ([A] Tables 16, 25)
    constant AS_REG_SR    : natural := 16#00#;
    constant AS_REG_CR1   : natural := 16#02#;
    constant AS_REG_CR2   : natural := 16#03#;
    constant AS_REG_FSR   : natural := 16#0A#;
    constant AS_REG_ID    : natural := 16#30#;
    constant AS_SR_PROTECT : byte_t := "10111100";      -- WP#EN, TBPSEL, BPSEL2-0
    constant AS_CR2_MLATS  : natural := 8;              -- Read latency; default, valid 8-15 up to 54 MHz

    -- Per-device parameters. All times in ns, except the output timing in ps.
    type dev_params_t is record
        addr_bytes    : positive;   -- Address bytes in EBh and write/erase commands
        read_dummy    : natural;    -- Clocks between the EBh mode byte and the first data
        id_bytes      : positive;   -- Bytes returned by 9Fh
        size_bytes    : positive;   -- Bytes per die (per CS#)
        page_bytes    : natural;    -- Program page size; 0 = writes of any length
        needs_erase   : boolean;    -- Erase before write, and poll BUSY after erase/program
        slow_sclk_hz  : positive;   -- Max SCLK for 05h / 9Fh
        t_powerup_ns  : natural;    -- Power-up / reset release to first (write) instruction
        t_reset_ns    : natural;    -- W25Q: 99h to next instruction. AS: RESET# low time
        t_cs_rd_ns    : natural;    -- Min CS# high after a read
        t_cs_wr_ns    : natural;    -- Min CS# high after a write
        t_out_valid_ps: natural;    -- Clock low to output valid (max)
        t_out_hold_ps : natural;    -- Output hold after clock low (min)
    end record;

    function dev_params(dev : device_t) return dev_params_t;

    -- SCLK cycles from opcode start to the first data clock of an EBh read
    function read_overhead_clocks(dev : device_t) return natural;

    -- True if a 9Fh result matches the device. id(31 downto 32 - 8 * id_bytes) holds the bytes
    -- in the order they arrive; unused low bytes are ignored.
    function id_ok(dev : device_t; id : std_logic_vector(31 downto 0)) return boolean;

end package qspi_pkg;

package body qspi_pkg is

    function dev_params(dev : device_t) return dev_params_t is
    begin
        case dev is
            when DEV_W25Q128JV =>
                return (addr_bytes     => 3,                -- [W] p.23
                        read_dummy     => 4,                -- [W] p.33
                        id_bytes       => 3,                -- [W] p.50
                        size_bytes     => 16 * 1024 * 1024, -- 128 Mbit
                        page_bytes     => 256,              -- [W] p.36
                        needs_erase    => true,
                        slow_sclk_hz   => 133_000_000,      -- No slower commands
                        t_powerup_ns   => 5_000_000,        -- tPUW 5 ms ([W] p.61)
                        t_reset_ns     => 30_000,           -- tRST 30 us ([W] p.65)
                        t_cs_rd_ns     => 10,               -- tSHSL1 ([W] p.64)
                        t_cs_wr_ns     => 50,               -- tSHSL2
                        t_out_valid_ps => 6_000,            -- tCLQV
                        t_out_hold_ps  => 1_500);           -- tCLQX
            when DEV_AS308G208 =>
                return (addr_bytes     => 4,                -- [A] p.40
                        read_dummy     => AS_CR2_MLATS,     -- [A] Tables 25, 31
                        id_bytes       => 4,                -- [A] Table 34
                        size_bytes     => 512 * 1024 * 1024,-- 4 Gbit per CS# ([A] Table 2, Fig. 12)
                        page_bytes     => 0,
                        needs_erase    => false,
                        slow_sclk_hz   => 40_000_000,       -- 05h, 9Fh ([A] Table 34)
                        t_powerup_ns   => 25_000_000,       -- tPU 25 ms ([A] Table 10)
                        t_reset_ns     => 1_000,            -- RESET# low, not specified (Q-A2)
                        t_cs_rd_ns     => 20,               -- tCS1 ([A] Table 44)
                        t_cs_wr_ns     => 600,              -- tCS3
                        t_out_valid_ps => 9_000,            -- tCO ([A] Table 48)
                        t_out_hold_ps  => 1_000);           -- tOH
        end case;
    end function;

    function read_overhead_clocks(dev : device_t) return natural is
        constant P : dev_params_t := dev_params(dev);
    begin
        -- Opcode (8 clocks on IO0) + address and mode byte (2 clocks per byte) + dummy/latency
        return 8 + 2 * P.addr_bytes + 2 + P.read_dummy;
    end function;

    function id_ok(dev : device_t; id : std_logic_vector(31 downto 0)) return boolean is
    begin
        case dev is
            when DEV_W25Q128JV =>
                return id(31 downto 8) = x"EF4018";                 -- W25Q128JV-IQ ([W] p.21)
            when DEV_AS308G208 =>
                -- E6 = Avalanche, 2 = Dual-Quad SPI, 1 = 3 V, 2 = -40..125 C, 01 = 54 MHz;
                -- density 1010 (4 Gb) or 1100 (8 Gb), see Q-A1 ([A] Table 22)
                return id(31 downto 12) = x"E6212" and id(7 downto 0) = x"01"
                       and (id(11 downto 8) = "1010" or id(11 downto 8) = "1100");
        end case;
    end function;

end package body qspi_pkg;
