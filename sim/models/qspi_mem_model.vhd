-- Behavioural model of one QSPI memory die (simulation only)
--   DEVICE = DEV_W25Q128JV: Winbond W25Q128JVSSIQ, 16 MB NOR flash.
--   DEVICE = DEV_AS308G208: one CS# of the Avalanche AS308G208 MRAM (512 MB). A dual-die
--            setup uses two instances, one on IO[3:0] and one on IO[7:4].
--   Facts and references: documentation/device_facts.md. SPI mode 0, SDR only.
--
-- Commands
--   both: 06h WREN, 04h WRDI, 05h RDSR, 9Fh RDID, EBh read (1-4-4, mode byte, dummy/latency)
--   W25Q: 35h/15h RDSR2/3, 01h/31h/11h WRSR1/2/3 (BUSY for T_W), 66h+99h reset (T_RST),
--         20h sector erase (BUSY for T_SE), 02h page program 1-1-1, 32h page program 1-1-4
--         (BUSY for T_PP; data wraps within the 256-byte page; programming ANDs into the array).
--         Quad commands need QE = 1 (QE_INIT; fixed when QE_INIT = '1', as on the -IQ part).
--   AS:   70h RDFSR, 65h RDAR / 71h WRAR (1-1-1, 4 address bytes, RDAR with CR2 latency),
--         01h WRSR, 02h write 1-1-1, D2h write 1-4-4 (XIP byte, no latency). RESET# pin
--         (registers return to their defaults, then T_PU before the next command).
--         RDAR of 30h..33h returns the device ID bytes (assumption, Q-A1).
--   Register reads (05h/35h/15h/70h/65h, 9Fh) repeat until CS# goes high; 05h is live (BUSY).
--   Memory reads wrap at the end of the die.
--
-- Output timing: each SCLK falling edge launches the next output bit/nibble. The pins go to
-- 'X' T_OUT_HOLD after the falling edge and to the new value T_OUT_VALID after it, both plus
-- T_BOARD (the round trip: SCLK out + data back). CS# high releases the pins after the output
-- disable time.
--
-- Checks (each reports an error and increments err_count):
--   power-up / reset recovery not over at CS# low; SCLK high at CS# low; CS# high time too short
--   (read vs write); SCLK faster than allowed for the command; input IO not '0'/'1' or changed
--   within the setup time; contention (another driver while the model drives); unsupported
--   opcode; quad command with QE = 0; mode/XIP byte other than Fxh (continuous read / XIP
--   would be entered); address outside the die; write/erase without WEL/WREN; command while
--   BUSY (W25Q, except 05h); 99h not directly after 66h; program/erase/status write not ending
--   on a byte boundary; write to a protected device (protection is not modelled, so any set
--   protection bit is an error). A wrong host latency shows up as an undriven mode byte or as
--   contention.
--
-- Time generics set to 0 ns use the datasheet value (use short values in testbenches).
-- W25_ID, AS_SR_INIT, AS_CR2_INIT and REG_WRITE_IGNORE inject faults / non-default states.

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.qspi_pkg.all;
use work.qspi_model_pkg.all;

entity qspi_mem_model is
    generic (
        DEVICE       : device_t  := DEV_W25Q128JV;
        DIE          : natural   := 1;          -- Only used in messages
        PRELOAD_SEED : natural   := 0;          -- 0: unwritten bytes read FFh; else pattern_byte
        QE_INIT      : std_logic := '1';        -- W25Q: QE at power-up (fixed when '1')
        AS_ID        : std_logic_vector(31 downto 0) := x"E6212C01";
        W25_ID       : std_logic_vector(23 downto 0) := x"EF4018";
        -- Fault injection / non-default state (testbenches)
        AS_SR_INIT   : std_logic_vector(7 downto 0) := x"00";   -- SR after power-up/RESET#
        AS_CR2_INIT  : natural range 0 to 15 := 8;               -- MLATS after power-up/RESET#
        REG_WRITE_IGNORE : boolean := false;                     -- Silently ignore register writes
        T_BOARD      : time := 0 ns;            -- Added to the output timing
        T_OUT_VALID  : time := 0 ns;            -- tCLQV / tCO
        T_OUT_HOLD   : time := 0 ns;            -- tCLQX / tOH
        T_PU         : time := 0 ns;            -- W25Q tPUW (writes only), AS tPU (all commands)
        T_RST        : time := 0 ns;            -- W25Q reset recovery (tRST)
        T_W          : time := 0 ns;            -- W25Q status register write (tW)
        T_PP         : time := 0 ns;            -- W25Q page program (tPP)
        T_SE         : time := 0 ns;            -- W25Q sector erase (tSE)
        VERBOSE      : boolean := false         -- Report every command
    );
    port (
        sclk      : in    std_logic;
        cs_n      : in    std_logic;
        reset_n   : in    std_logic := '1';    -- AS RESET#; leave open for the W25Q
        io        : inout std_logic_vector(3 downto 0);
        err_count : out   natural
    );
end entity qspi_mem_model;

architecture behav of qspi_mem_model is

    constant P   : dev_params_t := dev_params(DEVICE);
    constant W25 : boolean := DEVICE = DEV_W25Q128JV;

    function pick(t, dflt : time) return time is
    begin
        if t = 0 ns then
            return dflt;
        end if;
        return t;
    end function;

    function sel(c : boolean; a, b : time) return time is
    begin
        if c then
            return a;
        end if;
        return b;
    end function;

    constant TOV    : time := pick(T_OUT_VALID, P.t_out_valid_ps * 1 ps) + T_BOARD;
    constant TOH    : time := pick(T_OUT_HOLD, P.t_out_hold_ps * 1 ps) + T_BOARD;
    constant TDIS   : time := sel(W25, 7 ns, 9 ns) + T_BOARD;      -- tSHQZ / tHZCS
    constant TSU    : time := sel(W25, 1 ns, 4 ns);                -- tDVCH / tSU
    constant TPU    : time := pick(T_PU, P.t_powerup_ns * 1 ns);
    constant TRST   : time := pick(T_RST, P.t_reset_ns * 1 ns);
    constant TW     : time := pick(T_W, 10 ms);
    constant TPP    : time := pick(T_PP, 400 us);
    constant TSE    : time := pick(T_SE, 45 ms);
    constant TCS_RD : time := P.t_cs_rd_ns * 1 ns;
    constant TCS_WR : time := P.t_cs_wr_ns * 1 ns;
    constant SIZE   : positive := P.size_bytes;
    constant NAME   : string := "MODEL " & device_t'image(DEVICE) & " die " & integer'image(DIE);

    subtype reg_t is std_logic_vector(7 downto 0);

    signal drv      : std_logic_vector(3 downto 0) := (others => 'Z');
    signal err_main : natural := 0;
    signal err_cont : natural := 0;
begin
    io        <= drv;
    err_count <= err_main + err_cont;

    -- Contention: a pin differs from what the model drives. Checked when the pins change, so the
    -- resolution delta right after a change of drv is not flagged.
    contention : process (io)
        variable errors : natural := 0;
    begin
        for i in 0 to 3 loop
            if (drv(i) = '0' or drv(i) = '1') and io(i) /= drv(i) then
                report NAME & ": contention on IO" & integer'image(i) & " (model drives "
                       & std_logic'image(drv(i)) & ", pin is " & std_logic'image(io(i)) & ")"
                       severity error;
                errors := errors + 1;
                err_cont <= errors;
            end if;
        end loop;
    end process;

    main : process
        type src_kind_t  is (SRC_MEM, SRC_REGS, SRC_SR1, SRC_SR_AS);
        type sink_kind_t is (SINK_NONE, SINK_PAGE, SINK_MEM, SINK_REG);
        type reg_arr_t   is array (0 to 255) of reg_t;
        type bool_arr_t  is array (0 to 255) of boolean;

        variable mem         : mem_t;
        variable errors      : natural := 0;

        -- Registers. W25Q: sr1 (BUSY/WEL kept separately), sr2, sr3. AS: sr (WREN separately), cr1, cr2.
        variable sr1, sr2, sr3 : reg_t;
        variable sr, cr1, cr2  : reg_t;
        variable wel           : boolean := false;

        variable busy_until  : time := 0 ns;      -- W25Q BUSY
        variable ready_at    : time := 0 ns;      -- AS power-up/reset, W25Q reset recovery
        variable write_at    : time := 0 ns;      -- W25Q: writes allowed (tPUW)
        variable t_cs_rise   : time := 0 ns;
        variable seen_cs     : boolean := false;
        variable last_write  : boolean := false;
        variable prev_op     : natural := 0;

        -- Current command
        variable op          : natural range 0 to 255 := 0;
        variable ok          : boolean;
        variable f_max       : positive;
        variable t_rise_prev : time := 0 ns;
        variable first_rise  : boolean := true;
        variable freq_err    : boolean := false;  -- SCLK too fast already reported for this command
        variable is_write    : boolean;           -- Use the write CS# high time afterwards
        variable clear_wel   : boolean;
        variable new_busy    : time;              -- W25Q BUSY time starting at CS# high
        variable do_reset    : boolean;           -- W25Q 99h

        -- Output source and input sink
        variable src         : src_kind_t := SRC_REGS;
        variable src_addr    : natural := 0;
        variable src_bytes    : reg_arr_t;
        variable src_len     : positive := 1;
        variable src_idx     : natural := 0;
        variable sink        : sink_kind_t := SINK_NONE;
        variable sink_addr   : natural := 0;
        variable sink_count  : natural := 0;
        variable reg_addr    : natural := 0;
        variable page_base   : natural := 0;
        variable page_off    : natural := 0;
        variable page_data   : reg_arr_t;
        variable page_valid  : bool_arr_t;
        variable whole_bytes : boolean := true;

        variable v           : unsigned(31 downto 0);
        variable addr        : natural;
        variable extra       : natural;
        variable old_b       : reg_t;

        procedure err(msg : string) is
        begin
            report NAME & ": " & msg severity error;
            errors   := errors + 1;
            err_main <= errors;
        end procedure;

        procedure info(msg : string) is
        begin
            if VERBOSE then
                report NAME & ": " & msg;
            end if;
        end procedure;

        impure function ophex return string is
        begin
            return to_hstring(to_unsigned(op, 8)) & "h";
        end function;

        procedure set_defaults is
        begin
            sr1 := x"00";
            sr2 := x"00";
            sr2(W25_SR2_QE) := QE_INIT;
            sr3 := x"60";                       -- DRV1-0 = 11 (25 %)
            sr  := AS_SR_INIT;
            cr1 := x"60";                       -- ODSEL = 011 (Table 23)
            cr2 := std_logic_vector(to_unsigned(AS_CR2_INIT, 8));
            wel := false;
        end procedure;

        impure function sr1_live return reg_t is
            variable s : reg_t := sr1;
        begin
            s(W25_SR1_BUSY) := '1' when now < busy_until else '0';
            s(W25_SR1_WEL)  := '1' when wel else '0';
            return s;
        end function;

        impure function sr_as_live return reg_t is
            variable s : reg_t := sr;
        begin
            s(1) := '1' when wel else '0';
            return s;
        end function;

        impure function as_reg(a : natural) return reg_t is
        begin
            case a is
                when 16#00# => return sr_as_live;
                when 16#02# => return cr1;
                when 16#03# => return cr2;
                when 16#0A# => return x"80";                         -- FSR: ready
                when 16#30# => return AS_ID(31 downto 24);
                when 16#31# => return AS_ID(23 downto 16);
                when 16#32# => return AS_ID(15 downto 8);
                when 16#33# => return AS_ID(7 downto 0);
                when others => return x"00";
            end case;
        end function;

        impure function is_protected return boolean is
        begin
            if W25 then
                return (sr1 and W25_SR1_PROTECT) /= x"00" or sr2(W25_SR2_CMP) = '1'
                       or sr3(W25_SR3_WPS) = '1';
            end if;
            return (sr and AS_SR_PROTECT) /= x"00";
        end function;

        -- Next SCLK rising edge; ok = false if CS# went high or RESET# low instead
        procedure wait_rise(ok : out boolean) is
        begin
            wait until rising_edge(sclk) or cs_n = '1' or reset_n = '0';
            ok := cs_n = '0' and reset_n = '1';
            if cs_n = '0' and reset_n = '1' then
                if not first_rise and now - t_rise_prev < 1 sec / f_max and not freq_err then
                    freq_err := true;
                    err("SCLK period " & time'image(now - t_rise_prev) & " too short for opcode "
                        & ophex & " (max " & integer'image(f_max / 1_000_000) & " MHz)");
                end if;
                first_rise  := false;
                t_rise_prev := now;
            end if;
        end procedure;

        procedure wait_fall(ok : out boolean) is
        begin
            wait until falling_edge(sclk) or cs_n = '1' or reset_n = '0';
            ok := cs_n = '0' and reset_n = '1';
        end procedure;

        -- Receive nclk clocks of input, 1 bit (IO0) or 4 bits (IO3:0) per clock, MSB first
        procedure get_in(quad : boolean; nclk : natural; val : out unsigned(31 downto 0);
                         ok : out boolean) is
            variable r : unsigned(31 downto 0) := (others => '0');
            variable o : boolean := true;
        begin
            for k in 1 to nclk loop
                wait_rise(o);
                exit when not o;
                if quad then
                    if is_x(io) then
                        err("IO3:0 not driven while receiving (opcode " & ophex & ")");
                    elsif io'last_event < TSU then
                        err("IO3:0 setup time violated (opcode " & ophex & ")");
                    end if;
                    r := r(27 downto 0) & unsigned(to_01(io));
                else
                    if is_x(io(0)) then
                        err("IO0 not driven while receiving (opcode " & ophex & ")");
                    elsif io(0)'last_event < TSU then
                        err("IO0 setup time violated (opcode " & ophex & ")");
                    end if;
                    r := r(30 downto 0) & to_01(io(0));
                end if;
            end loop;
            val := r;
            ok  := o;
        end procedure;

        procedure skip_clocks(n : natural; ok : out boolean) is
            variable o : boolean := true;
        begin
            for k in 1 to n loop
                wait_rise(o);
                exit when not o;
            end loop;
            ok := o;
        end procedure;

        -- Address of a memory access (die byte address)
        procedure take_addr(a : unsigned(31 downto 0)) is
        begin
            if W25 then
                addr := to_integer(a(23 downto 0));
            else
                if a(31 downto 29) /= "000" then
                    err("address " & to_hstring(a) & "h is outside the die");
                end if;
                addr := to_integer(a(28 downto 0));
            end if;
        end procedure;

        -- Mode / XIP byte after the address: must be Fxh
        procedure check_mode(m : unsigned(31 downto 0)) is
        begin
            if m(7 downto 4) /= x"F" then
                if W25 and m(5 downto 4) = "10" then
                    err("mode byte " & to_hstring(m(7 downto 0)) & "h enters continuous read mode");
                elsif not W25 and m(7 downto 4) = x"A" then
                    err("XIP byte " & to_hstring(m(7 downto 0)) & "h enables XIP");
                else
                    err("mode byte " & to_hstring(m(7 downto 0)) & "h, expected Fxh");
                end if;
            end if;
        end procedure;

        -- Drive one output unit (IO1 in SPI, IO3:0 in quad) for the cycle that starts now
        procedure drive_unit(quad : boolean; val : std_logic_vector(3 downto 0)) is
        begin
            if quad then
                drv <= transport (others => 'X') after TOH;
                drv <= transport val after TOV;
            else
                drv(1) <= transport 'X' after TOH;
                drv(1) <= transport val(0) after TOV;
            end if;
        end procedure;

        impure function next_out_byte return reg_t is
            variable b : reg_t;
        begin
            case src is
                when SRC_MEM =>
                    b := std_logic_vector(to_unsigned(mem.read(src_addr), 8));
                    src_addr := (src_addr + 1) mod SIZE;
                when SRC_REGS =>
                    b := src_bytes(src_idx);
                    src_idx := (src_idx + 1) mod src_len;
                when SRC_SR1 =>
                    b := sr1_live;
                when SRC_SR_AS =>
                    b := sr_as_live;
            end case;
            return b;
        end function;

        procedure set_src_regs(b0 : reg_t) is
        begin
            src := SRC_REGS;  src_bytes(0) := b0;  src_len := 1;  src_idx := 0;
        end procedure;

        -- Send bytes from the source until CS# goes high. Each falling edge launches a unit.
        procedure send(quad : boolean) is
            variable b : reg_t;
            variable o : boolean := true;
        begin
            while o loop
                b := next_out_byte;
                if quad then
                    for n in 1 downto 0 loop
                        wait_fall(o);
                        exit when not o;
                        drive_unit(true, b(4 * n + 3 downto 4 * n));
                        wait_rise(o);
                        exit when not o;
                    end loop;
                else
                    for n in 7 downto 0 loop
                        wait_fall(o);
                        exit when not o;
                        drive_unit(false, "000" & b(n));
                        wait_rise(o);
                        exit when not o;
                    end loop;
                end if;
            end loop;
        end procedure;

        procedure write_reg(b : reg_t) is
        begin
            if REG_WRITE_IGNORE then
                info("register write ignored (REG_WRITE_IGNORE)");
            elsif W25 then
                case op is
                    when 16#01# =>                     -- SRP, SEC, TB, BP2-0
                        sr1(7 downto 2) := b(7 downto 2);
                    when 16#31# =>                     -- CMP, LB3-1 (OTP), QE (unless fixed), SRL
                        sr2(6) := b(6);
                        sr2(5 downto 3) := sr2(5 downto 3) or b(5 downto 3);
                        if QE_INIT = '0' then
                            sr2(1) := b(1);
                        end if;
                        sr2(0) := b(0);
                    when others =>                     -- 11h: DRV1-0, WPS
                        sr3(6 downto 5) := b(6 downto 5);
                        sr3(2) := b(2);
                end case;
            else
                case reg_addr is
                    when 16#00# =>                     -- WP#EN, TBPSEL, BPSEL2-0
                        sr(7) := b(7);
                        sr(5 downto 2) := b(5 downto 2);
                    when 16#02# =>                     -- ODSEL, MAPLK, WRENS
                        cr1(7 downto 5) := b(7 downto 5);
                        cr1(2 downto 0) := b(2 downto 0);
                    when 16#03# =>                     -- MLATS
                        cr2(3 downto 0) := b(3 downto 0);
                    when others =>
                        err("write to read-only/unknown register "
                            & to_hstring(to_unsigned(reg_addr, 8)) & "h");
                end case;
            end if;
        end procedure;

        procedure deliver(b : reg_t) is
        begin
            case sink is
                when SINK_PAGE =>
                    page_data((page_off + sink_count) mod 256)  := b;
                    page_valid((page_off + sink_count) mod 256) := true;
                when SINK_MEM =>
                    mem.write((sink_addr + sink_count) mod SIZE, to_integer(unsigned(b)));
                when SINK_REG =>
                    if sink_count = 0 then
                        write_reg(b);
                    end if;
                when SINK_NONE =>
                    null;
            end case;
            sink_count := sink_count + 1;
        end procedure;

        -- Receive bytes into the sink until CS# goes high; whole_bytes = ended on a byte boundary
        procedure receive(quad : boolean) is
            variable r     : unsigned(31 downto 0);
            variable o     : boolean := true;
            variable nunit : natural := 0;
            variable b     : reg_t := x"00";
        begin
            sink_count := 0;
            loop
                if quad then
                    get_in(true, 1, r, o);
                    exit when not o;
                    b := b(3 downto 0) & std_logic_vector(r(3 downto 0));
                    nunit := (nunit + 1) mod 2;
                else
                    get_in(false, 1, r, o);
                    exit when not o;
                    b := b(6 downto 0) & r(0);
                    nunit := (nunit + 1) mod 8;
                end if;
                if nunit = 0 then
                    deliver(b);
                end if;
            end loop;
            whole_bytes := nunit = 0;
        end procedure;

        -- Wait for CS# high (or RESET#), counting extra SCLK rising edges
        procedure finish(n_extra : out natural) is
            variable n : natural := 0;
        begin
            while cs_n = '0' and reset_n = '1' loop
                wait until rising_edge(sclk) or cs_n = '1' or reset_n = '0';
                if cs_n = '0' and reset_n = '1' then
                    n := n + 1;
                end if;
            end loop;
            n_extra := n;
        end procedure;

        -- Write commands: WEL/WREN and protection checks. Returns true if the write may proceed.
        impure function write_allowed return boolean is
        begin
            if not wel and not (not W25 and cr1(1 downto 0) = "01") then
                return false;
            end if;
            return not is_protected;
        end function;

        procedure report_write_refused is
        begin
            if is_protected then
                err("write/erase " & ophex & " to a protected device (protection bits set)");
            else
                err("write/erase " & ophex & " without WEL/WREN");
            end if;
        end procedure;

        procedure w25_command is
        begin
            case op is
                when 16#06# =>
                    if now < write_at then
                        err("WREN before tPUW (" & time'image(write_at) & ")");
                    else
                        wel := true;
                    end if;
                when 16#04# =>
                    wel := false;
                when 16#05# =>
                    src := SRC_SR1;
                    send(false);
                when 16#35# =>
                    set_src_regs(sr2);
                    send(false);
                when 16#15# =>
                    set_src_regs(sr3);
                    send(false);
                when 16#9F# =>
                    src := SRC_REGS;  src_bytes(0) := W25_ID(23 downto 16);
                    src_bytes(1) := W25_ID(15 downto 8);  src_bytes(2) := W25_ID(7 downto 0);
                    src_len := 3;  src_idx := 0;
                    send(false);
                when 16#01# | 16#31# | 16#11# =>
                    is_write := true;
                    if wel then
                        sink := SINK_REG;
                    else
                        err("status register write " & ophex & " without WEL");
                        sink := SINK_NONE;
                    end if;
                    receive(false);
                    if not whole_bytes or sink_count = 0 then
                        err("status register write " & ophex & " not ending on a byte boundary");
                    end if;
                    if wel then
                        new_busy  := TW;
                        clear_wel := true;
                    end if;
                when 16#66# =>
                    null;
                when 16#99# =>
                    if prev_op = 16#66# then
                        do_reset := true;
                    else
                        err("99h (reset) not directly after 66h");
                    end if;
                when 16#20# =>
                    is_write := true;
                    get_in(false, 24, v, ok);
                    if ok then
                        take_addr(v);
                        finish(extra);
                        if extra mod 8 /= 0 then
                            err("sector erase not ending on a byte boundary");
                        elsif not write_allowed then
                            report_write_refused;
                        else
                            info("erase sector " & to_hstring(to_unsigned(addr - addr mod 4096, 24)) & "h");
                            for i in 0 to 4095 loop
                                mem.write(addr - addr mod 4096 + i, 255);
                            end loop;
                            new_busy  := TSE;
                            clear_wel := true;
                        end if;
                    end if;
                when 16#02# | 16#32# =>
                    is_write := true;
                    if op = 16#32# and sr2(W25_SR2_QE) = '0' then
                        err("quad page program with QE = 0");
                    else
                        get_in(false, 24, v, ok);
                        if ok then
                            take_addr(v);
                            page_base  := addr - addr mod 256;
                            page_off   := addr mod 256;
                            page_valid := (others => false);
                            sink       := SINK_PAGE;
                            receive(op = 16#32#);
                            if not whole_bytes or sink_count = 0 then
                                err("page program not ending on a byte boundary");
                            elsif not write_allowed then
                                report_write_refused;
                            else
                                info("program " & integer'image(sink_count) & " bytes at "
                                     & to_hstring(to_unsigned(addr, 24)) & "h");
                                if sink_count > 256 then
                                    info("more than 256 bytes: wrapped within the page");
                                end if;
                                for i in 0 to 255 loop
                                    if page_valid(i) then
                                        old_b := std_logic_vector(to_unsigned(mem.read(page_base + i), 8));
                                        mem.write(page_base + i,
                                                  to_integer(unsigned(old_b and page_data(i))));
                                    end if;
                                end loop;
                                new_busy  := TPP;
                                clear_wel := true;
                            end if;
                        end if;
                    end if;
                when 16#EB# =>
                    if sr2(W25_SR2_QE) = '0' then
                        err("EBh with QE = 0");
                    else
                        get_in(true, 6, v, ok);
                        if ok then
                            take_addr(v);
                            get_in(true, 2, v, ok);
                        end if;
                        if ok then
                            check_mode(v);
                            skip_clocks(dev_params(DEVICE).read_dummy, ok);
                        end if;
                        if ok then
                            src := SRC_MEM;
                            src_addr := addr;
                            send(true);
                        end if;
                    end if;
                when others =>
                    err("unsupported opcode " & ophex);
            end case;
        end procedure;

        procedure as_command is
        begin
            case op is
                when 16#06# =>
                    wel := true;
                when 16#04# =>
                    wel := false;
                when 16#05# =>
                    f_max := 40_000_000;
                    src := SRC_SR_AS;
                    send(false);
                when 16#70# =>
                    f_max := 50_000_000;
                    set_src_regs(x"80");
                    send(false);
                when 16#9F# =>
                    f_max := 40_000_000;
                    src := SRC_REGS;  src_len := 4;  src_idx := 0;
                    for i in 0 to 3 loop
                        src_bytes(i) := AS_ID(31 - 8 * i downto 24 - 8 * i);
                    end loop;
                    send(false);
                when 16#65# =>
                    get_in(false, 32, v, ok);
                    if ok then
                        reg_addr := to_integer(v(7 downto 0));
                        skip_clocks(to_integer(unsigned(cr2(3 downto 0))), ok);
                    end if;
                    if ok then
                        set_src_regs(as_reg(reg_addr));
                        send(false);
                    end if;
                when 16#71# | 16#01# =>
                    is_write  := true;
                    clear_wel := true;                  -- Register writes always clear WREN
                    reg_addr  := 0;
                    ok := true;
                    if op = 16#71# then
                        get_in(false, 32, v, ok);
                        reg_addr := to_integer(v(7 downto 0));
                    end if;
                    if ok then
                        if wel then
                            sink := SINK_REG;
                        else
                            err("register write " & ophex & " without WREN");
                            sink := SINK_NONE;
                        end if;
                        receive(false);
                        if not whole_bytes or sink_count = 0 then
                            err("register write " & ophex & " not ending on a byte boundary");
                        end if;
                    end if;
                when 16#02# | 16#D2# =>
                    is_write := true;
                    get_in(op = 16#D2#, 8 + 24 * boolean'pos(op = 16#02#), v, ok);
                    if ok then
                        take_addr(v);
                        if op = 16#D2# then
                            get_in(true, 2, v, ok);
                            if ok then
                                check_mode(v);
                            end if;
                        end if;
                    end if;
                    if ok then
                        if write_allowed then
                            sink := SINK_MEM;
                        else
                            report_write_refused;
                            sink := SINK_NONE;
                        end if;
                        sink_addr := addr;
                        receive(op = 16#D2#);
                        info("wrote " & integer'image(sink_count) & " bytes at "
                             & to_hstring(to_unsigned(addr, 32)) & "h");
                        if cr1(1 downto 0) = "00" then
                            clear_wel := true;
                        end if;
                    end if;
                when 16#EB# =>
                    get_in(true, 8, v, ok);
                    if ok then
                        take_addr(v);
                        get_in(true, 2, v, ok);
                    end if;
                    if ok then
                        check_mode(v);
                        skip_clocks(to_integer(unsigned(cr2(3 downto 0))), ok);
                    end if;
                    if ok then
                        src := SRC_MEM;
                        src_addr := addr;
                        send(true);
                    end if;
                when others =>
                    err("unsupported opcode " & ophex);
            end case;
        end procedure;

        procedure hw_reset is
        begin
            info("RESET#");
            drv <= (others => 'Z');
            if reset_n = '0' then
                wait until reset_n = '1';
            end if;
            set_defaults;
            ready_at := now + TPU;
        end procedure;
    begin
        set_defaults;
        mem.configure(PRELOAD_SEED, 255);
        if W25 then
            write_at := TPU;
        else
            ready_at := TPU;
        end if;

        loop
            wait until cs_n = '0' or reset_n = '0';
            if reset_n = '0' then
                if not W25 then
                    hw_reset;
                end if;
                next;
            end if;

            -- CS# went low
            if sclk /= '0' then
                err("SCLK high when CS# went low (mode 0)");
            end if;
            if seen_cs and last_write and now - t_cs_rise < TCS_WR then
                err("CS# high for " & time'image(now - t_cs_rise) & " after a write, min "
                    & time'image(TCS_WR));
            elsif seen_cs and now - t_cs_rise < TCS_RD then
                err("CS# high for " & time'image(now - t_cs_rise) & ", min " & time'image(TCS_RD));
            end if;
            if now < ready_at then
                err("command during power-up/reset recovery (until " & time'image(ready_at) & ")");
            end if;

            if W25 then
                f_max := 133_000_000;
            else
                f_max := 54_000_000;
            end if;
            first_rise := true;
            freq_err   := false;
            is_write   := false;
            clear_wel  := false;
            new_busy   := 0 ns;
            do_reset   := false;
            sink       := SINK_NONE;
            op         := 0;

            get_in(false, 8, v, ok);
            if ok then
                op := to_integer(v(7 downto 0));
                info("opcode " & ophex);
                if W25 and now < busy_until and op /= 16#05# then
                    err("opcode " & ophex & " while BUSY");
                elsif W25 then
                    w25_command;
                else
                    as_command;
                end if;
            end if;

            finish(extra);
            drv <= transport (others => 'Z') after TDIS;

            if reset_n = '0' then
                if not W25 then
                    hw_reset;
                end if;
                seen_cs := false;
                next;
            end if;

            -- CS# went high
            t_cs_rise  := now;
            seen_cs    := true;
            last_write := is_write;
            prev_op    := op;
            if clear_wel then
                wel := false;
            end if;
            if new_busy > 0 ns then
                busy_until := now + new_busy;
            end if;
            if do_reset then
                info("software reset");
                wel        := false;
                busy_until := now;
                ready_at   := now + TRST;
            end if;
        end loop;
    end process;
end architecture behav;
