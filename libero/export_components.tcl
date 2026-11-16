# export_components.tcl
#
# Exports every component of the Libero project (HDL+ core definitions,
# configured IP cores and the SmartDesign TOP) as Tcl into libero/components/.
# create_project.tcl sources those files to rebuild the project from scratch.
#
# Run it again whenever a component changes (SmartDesign edited, core
# reconfigured, HDL+ core ports/generics/bus interfaces changed) and commit
# the result.
#
#   GUI:    with the project open: Project -> Execute Script... -> this file
#   Batch:  tools/export_components.sh   (Libero GUI must be closed: one license)
#
# The MSS is not exported: it is imported from mss/MSS_simple.cxz.
#
# Absolute paths below the repository root are rewritten to "$repo_root/...",
# so the exported files do not depend on where the repository is checked out.

set script_dir [file dirname [file normalize [info script]]]
set repo_root  [file dirname $script_dir]
set out_dir    [file join $script_dir components]

# HDL+ cores first, then the cores TOP instantiates, then TOP itself.
set hdl_cores  {axi_sys_ctrl bfic_block_producer block_arbiter pulse_stretch qspi_board}
set components {PF_CCC_C0 CORERESET INIT_MONITOR AXI_IC BLOCK_FIFO_CORE TOP}

set opened_here 0
if {[info exists argc] && $argc > 0} {
    open_project -file [file normalize [lindex $argv 0]] -do_backup_on_convert 0
    set opened_here 1
}

file mkdir $out_dir

# Replace {<repo_root>/x} and "<repo_root>/x" with "$repo_root/x".
proc make_relocatable {path repo_root} {
    set f [open $path r]
    set text [read $f]
    close $f
    # \x7b / \x7d are the brace characters (written as escapes to keep this
    # proc body brace-balanced); ***= would not allow the capture group.
    set root [string map {. \\. + \\+} $repo_root]
    regsub -all "\\x7b$root/(\\S*?)\\x7d" $text {"$repo_root/\1"} text
    set text [string map [list "\"$repo_root/" "\"\$repo_root/"] $text]
    set f [open $path w]
    puts -nonewline $f $text
    close $f
    if {[string first $repo_root $text] >= 0} {
        puts "WARNING: $path still contains the absolute path $repo_root"
    }
}

set failed {}
foreach c [concat $hdl_cores $components] {
    set out [file join $out_dir $c.tcl]
    file delete $out
    if {[catch {export_component_to_tcl -component $c -library {work} -package {} -file $out} msg]
            || ![file exists $out]} {
        puts "ERROR: export of $c failed: $msg"
        lappend failed $c
    } else {
        make_relocatable $out $repo_root
        puts "Exported $c -> $out"
    }
}

if {$opened_here} {
    close_project -save 0
}

if {[llength $failed] > 0} {
    error "export_components.tcl: failed for: $failed"
}
puts "export_components.tcl: done"
