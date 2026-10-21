-- Simulation support for qspi_mem_model
--   pattern_byte  Deterministic preload content: byte at a die address for a seed. Testbenches
--                 use it to compute the expected data of a preloaded model.
--   mem_t         Sparse byte memory (hashed 256-byte pages, allocated on first write), so a
--                 512 MB address space costs only what is written. Unwritten bytes read as
--                 pattern_byte(addr, seed), or as the blank value when seed = 0.

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

package qspi_model_pkg is

    function pattern_byte(addr : natural; seed : positive) return std_logic_vector;

    type mem_t is protected
        procedure configure(seed : natural; blank : natural);
        impure function read(addr : natural) return natural;           -- 0 .. 255
        procedure write(addr : natural; data : natural);
    end protected mem_t;

end package qspi_model_pkg;

package body qspi_model_pkg is

    function pattern_byte(addr : natural; seed : positive) return std_logic_vector is
        constant a0 : natural := addr mod 256;
        constant a1 : natural := (addr / 256) mod 256;
        constant a2 : natural := (addr / 65536) mod 256;
        constant a3 : natural := addr / 16777216;
    begin
        return std_logic_vector(to_unsigned((a0 + 3 * a1 + 5 * a2 + 7 * a3 + 11 * seed) mod 256, 8));
    end function;

    type mem_t is protected body
        constant PAGE    : positive := 256;
        constant NBUCKET : positive := 1024;

        type page_data_t is array (0 to PAGE - 1) of natural range 0 to 255;
        type page_t;
        type page_ptr_t is access page_t;
        type page_t is record
            key  : natural;
            data : page_data_t;
            nxt  : page_ptr_t;
        end record;
        type bucket_arr_t is array (0 to NBUCKET - 1) of page_ptr_t;

        variable buckets : bucket_arr_t := (others => null);
        variable seed_v  : natural := 0;
        variable blank_v : natural := 255;

        procedure configure(seed : natural; blank : natural) is
        begin
            seed_v  := seed;
            blank_v := blank;
        end procedure;

        impure function default_byte(addr : natural) return natural is
        begin
            if seed_v = 0 then
                return blank_v;
            end if;
            return to_integer(unsigned(pattern_byte(addr, seed_v)));
        end function;

        impure function find(key : natural) return page_ptr_t is
            variable p : page_ptr_t := buckets(key mod NBUCKET);
        begin
            while p /= null loop
                if p.key = key then
                    return p;
                end if;
                p := p.nxt;
            end loop;
            return null;
        end function;

        impure function read(addr : natural) return natural is
            variable p : page_ptr_t := find(addr / PAGE);
        begin
            if p = null then
                return default_byte(addr);
            end if;
            return p.data(addr mod PAGE);
        end function;

        procedure write(addr : natural; data : natural) is
            constant key : natural := addr / PAGE;
            variable p   : page_ptr_t := find(key);
        begin
            if p = null then
                p := new page_t;
                p.key := key;
                for i in 0 to PAGE - 1 loop
                    p.data(i) := default_byte(key * PAGE + i);
                end loop;
                p.nxt := buckets(key mod NBUCKET);
                buckets(key mod NBUCKET) := p;
            end if;
            p.data(addr mod PAGE) := data;
        end procedure;
    end protected body mem_t;

end package body qspi_model_pkg;
