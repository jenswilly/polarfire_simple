# create_project.tcl
#
# Creates the Libero project (polarfire_simple/polarfire_simple.prjx and
# everything Libero generates around it) from the sources in this repository.
# All paths are derived from the location of this script, so the repository
# can be checked out anywhere.
#
#   tools/create_project.sh [project_dir]
#
# or directly (Libero must NOT be started from inside the project folder,
# which does not exist yet):
#
#   libero SCRIPT:libero/create_project.tcl ["SCRIPT_ARGS:<project_dir>"]
#
# project_dir defaults to <repo>/polarfire_simple and must not exist yet
# (new_project refuses an existing directory).
#
# Inputs:
#   hdl/*.vhd                      linked as HDL sources
#   sim/tb_*.vhd                   the testbenches in $stimulus_files, linked
#   constraints/                   io.pdc, timing.sdc, qspi_ioreg.ndc, linked
#   mss/MSS_simple.cxz             MSS component (from the MSS Configurator)
#   libero/components/*.tcl        HDL+ cores, IP cores and SmartDesign TOP,
#                                  written by libero/export_components.tcl
#   hss/build/bootmode1/*.hex      eNVM boot mode 1 client (optional)

set script_dir [file dirname [file normalize [info script]]]
set repo_root  [file dirname $script_dir]

set project_name {polarfire_simple}
set project_dir  [file join $repo_root polarfire_simple]
if {[info exists argc] && $argc > 0 && [lindex $argv 0] ne ""} {
    set project_dir [file normalize [lindex $argv 0]]
}

# Components in dependency order: HDL+ cores, IP cores, then the SmartDesign.
set hdl_cores  {axi_sys_ctrl bfic_block_producer block_arbiter pulse_stretch qspi_board}
set ip_cores   {PF_CCC_C0 CORERESET INIT_MONITOR AXI_IC BLOCK_FIFO_CORE}
set root_name  {TOP}

set envm_hex [file join $repo_root hss build bootmode1 hss-envm-wrapper-bm1-p0.hex]

if {[file exists $project_dir]} {
    error "create_project.tcl: '$project_dir' already exists. Move or delete it first, or pass another project directory."
}

# ---------------------------------------------------------------------------
# Project and device (values as in the Project Settings of the original project)
# ---------------------------------------------------------------------------
new_project \
    -location $project_dir \
    -name $project_name \
    -project_description {} \
    -block_mode 0 \
    -standalone_peripheral_initialization 0 \
    -instantiate_in_smartdesign 1 \
    -ondemand_build_dh 1 \
    -use_relative_path 0 \
    -linked_files_root_dir_env {} \
    -hdl {VHDL} \
    -family {PolarFireSoC} \
    -die {MPFS095T} \
    -package {FCSG325} \
    -speed {-1} \
    -die_voltage {1.0} \
    -part_range {EXT} \
    -adv_options {IO_DEFT_STD:LVCMOS 1.8V} \
    -adv_options {RESERVEMIGRATIONPINS:1} \
    -adv_options {RESTRICTPROBEPINS:1} \
    -adv_options {RESTRICTSPIPINS:0} \
    -adv_options {SYSTEM_CONTROLLER_SUSPEND_MODE:0} \
    -adv_options {TARGETDEVICESFORMIGRATION:MPFS095T} \
    -adv_options {TEMPR:EXT} \
    -adv_options {UNUSED_MSS_IO_RESISTOR_PULL:None} \
    -adv_options {VCCI_1.2_VOLTR:EXT} \
    -adv_options {VCCI_1.5_VOLTR:EXT} \
    -adv_options {VCCI_1.8_VOLTR:EXT} \
    -adv_options {VCCI_2.5_VOLTR:EXT} \
    -adv_options {VCCI_3.3_VOLTR:EXT} \
    -adv_options {VOLTR:EXT}

# Libero writes HDL+ core definitions (component/User/Private/...) relative to
# its working directory, so work from inside the project folder.
cd $project_dir

project_settings \
    -hdl {VHDL} \
    -vhdl_mode {VHDL_2008} \
    -verilog_mode {SYSTEM_VERILOG}

# ---------------------------------------------------------------------------
# IP cores: make sure the versions the components were exported with are in
# the vault. Failing here is not fatal if the core is already there (offline).
# ---------------------------------------------------------------------------
foreach {vlnv repo} {
    Actel:DirectCore:COREAXI4INTERCONNECT:3.0.130 www.microchip-ip.com/repositories/DirectCore
    Actel:DirectCore:COREFIFO:4.0.139             www.microchip-ip.com/repositories/DirectCore
    Actel:DirectCore:CORERESET_PF:2.3.100         www.microchip-ip.com/repositories/DirectCore
    Actel:SgCore:PF_CCC:2.2.222                   www.microchip-ip.com/repositories/SgCore
    Microsemi:SgCore:PFSOC_INIT_MONITOR:1.0.309   www.microchip-ip.com/repositories/SgCore
} {
    if {[catch {download_core -vlnv $vlnv -location $repo} msg]} {
        puts "Note: download_core $vlnv: $msg"
    }
}

# ---------------------------------------------------------------------------
# Linked sources (nothing is copied into the project)
# ---------------------------------------------------------------------------
set link_args {}
foreach f [lsort [glob -directory [file join $repo_root hdl] *.vhd]] {
    lappend link_args -hdl_source $f
}
lappend link_args -io_pdc [file join $repo_root constraints io.pdc]
lappend link_args -sdc    [file join $repo_root constraints timing.sdc]
lappend link_args -ndc    [file join $repo_root constraints qspi_ioreg.ndc]
create_links {*}$link_args

build_design_hierarchy

# ---------------------------------------------------------------------------
# Components
# ---------------------------------------------------------------------------
import_mss_component -file [file join $repo_root mss MSS_simple.cxz]

foreach c [concat $hdl_cores $ip_cores] {
    source [file join $script_dir components $c.tcl]
}
build_design_hierarchy
source [file join $script_dir components $root_name.tcl]

build_design_hierarchy
set_root -module "${root_name}::work"

# ---------------------------------------------------------------------------
# Constraints: derived SDC plus the linked files, per tool
# ---------------------------------------------------------------------------
derive_constraints_sdc

set derived_sdc [file join $project_dir constraint ${root_name}_derived_constraints.sdc]
set timing_sdc  [file join $repo_root constraints timing.sdc]
set io_pdc      [file join $repo_root constraints io.pdc]
set ioreg_ndc   [file join $repo_root constraints qspi_ioreg.ndc]

organize_tool_files -tool {SYNTHESIZE} \
    -file $derived_sdc -file $ioreg_ndc \
    -module "${root_name}::work" -input_type {constraint}
organize_tool_files -tool {PLACEROUTE} \
    -file $io_pdc -file $derived_sdc -file $timing_sdc \
    -module "${root_name}::work" -input_type {constraint}
organize_tool_files -tool {VERIFYTIMING} \
    -file $derived_sdc -file $timing_sdc \
    -module "${root_name}::work" -input_type {constraint}

# ---------------------------------------------------------------------------
# eNVM boot mode 1 client (the HSS). configure_envm only works after
# "Generate FPGA Array Data", so the client configuration is written straight
# to designer/<root>/ENVM.cfg, where Libero keeps it and reads it from.
# -number_of_bytes must match the hex, so it is computed here. Skipped with a
# note if the HSS has not been built yet.
# ---------------------------------------------------------------------------
proc intel_hex_extent {path} {
    set f [open $path r]
    set base 0
    set lo {}
    set hi 0
    while {[gets $f line] >= 0} {
        if {[scan $line ":%2x%4x%2x" count addr type] != 3} continue
        switch -- $type {
            0 {
                set a [expr {$base + $addr}]
                if {$lo eq {} || $a < $lo} { set lo $a }
                if {$a + $count > $hi} { set hi [expr {$a + $count}] }
            }
            2 { scan [string range $line 9 12] %x seg; set base [expr {$seg << 4}] }
            4 { scan [string range $line 9 12] %x upper; set base [expr {$upper << 16}] }
        }
    }
    close $f
    return [list $lo $hi]
}

if {[file exists $envm_hex]} {
    lassign [intel_hex_extent $envm_hex] envm_lo envm_hi
    set envm_cfg [file join $project_dir designer $root_name ENVM.cfg]
    file mkdir [file dirname $envm_cfg]
    set f [open $envm_cfg w]
    puts $f "set_plain_text_client \\"
    puts $f "   -client_name {BOOT_MODE_1_ENVM_CLIENT}  \\"
    puts $f "   -number_of_bytes [expr {$envm_hi - $envm_lo}] \\"
    puts $f "   -content_type {MEMORY_FILE}  \\"
    puts $f "   -content_file_format {Intel-Hex}  \\"
    puts $f "   -content_file {$envm_hex}  \\"
    puts $f "   -mem_file_base_address {0x20220000}  \\"
    puts $f "   -start_page 0 \\"
    puts $f "   -use_for_simulation 0 \\"
    puts $f "   -reprogram 1 \\"
    puts $f "   -use_as_rom 0 \\"
    puts $f "   -include_in_digest 0 \\"
    puts $f "   -fabric_access_read 1 \\"
    puts $f "   -fabric_access_write 0 \\"
    puts $f "   -mss_access_read 1 \\"
    puts $f "   -mss_access_write 0"
    close $f
    puts "eNVM client: $envm_hex, [expr {$envm_hi - $envm_lo}] bytes"
} else {
    puts "Note: $envm_hex not found; eNVM client not configured."
    puts "      Build the HSS (hss/build_hss.sh) and add the Boot Mode 1 client in"
    puts "      Configure Design Initialization Data and Memories."
}

save_project
puts "create_project.tcl: created $project_dir/$project_name.prjx"
