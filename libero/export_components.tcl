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
#   Batch:  tools/export_components.sh     (Linux)
#           tools\export_components.bat    (Windows)
#           The Libero GUI must be closed (one license).
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
# Libero splits SCRIPT_ARGS at spaces, so join the pieces again.
if {[info exists argv] && [string trim [join $argv " "]] ne ""} {
    open_project -file [file normalize [string trim [join $argv " "]]] -do_backup_on_convert 0
    set opened_here 1
}

file mkdir $out_dir

# Replace {<repo_root>/x} and "<repo_root>/x" with "$repo_root/x".
# Plain string search instead of a regexp, so that paths with spaces or regexp
# characters work. The match ignores case and accepts \ as well as /, because
# on Windows the drive letter case and the separator may differ from
# [file normalize]. Written with LF line endings on every platform.
proc make_relocatable {path repo_root} {
    set f [open $path r]
    set text [read $f]
    close $f

    set lbrace [format %c 123]
    set rbrace [format %c 125]
    # Same length as $text, so indices can be used on both.
    set norm   [string tolower [string map {\\ /} $text]]
    set needle [string tolower [string map {\\ /} $repo_root]]/
    set out    {}
    set pos    0
    while {[set i [string first $needle $norm $pos]] >= 0} {
        set open_ch [string index $text [expr {$i - 1}]]
        if {$open_ch eq $lbrace} {
            set close_ch $rbrace
        } elseif {$open_ch eq "\""} {
            set close_ch "\""
        } else {
            append out [string range $text $pos [expr {$i + [string length $needle] - 1}]]
            set pos [expr {$i + [string length $needle]}]
            continue
        }
        set rest_start [expr {$i + [string length $needle]}]
        set j [string first $close_ch $text $rest_start]
        if {$j < 0} break
        set rest [string map {\\ /} [string range $text $rest_start [expr {$j - 1}]]]
        append out [string range $text $pos [expr {$i - 2}]]
        append out "\"\$repo_root/$rest\""
        set pos [expr {$j + 1}]
    }
    append out [string range $text $pos end]

    set f [open $path w]
    fconfigure $f -translation lf
    puts -nonewline $f $out
    close $f
    if {[string first $needle [string tolower [string map {\\ /} $out]]] >= 0} {
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
