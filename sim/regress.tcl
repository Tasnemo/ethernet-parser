# run every test of every written bench over a few seeds
# batch: vivado -mode batch -notrace -source sim/regress.tcl -tclargs [all|ethernet|ipv4|udp|top] [seeds...]

source -notrace [file join [file dirname [info script]] sim_lib.tcl]

set regress_tests [dict create \
    ethernet {eth_smoke_test eth_error_test eth_boundary_test eth_back_to_back_test eth_random_test} \
    ipv4     {ipv4_smoke_test ipv4_error_test ipv4_stream_error_test ipv4_stall_test ipv4_random_test}]

set which all
set seeds {1 2 3}
if {[llength $argv] > 0} { set which [lindex $argv 0] }
if {[llength $argv] > 1} { set seeds [lrange $argv 1 end] }
set benches [expr {$which eq "all" ? [dict keys $regress_tests] : [list $which]}]

set xsim [file join $::env(XILINX_VIVADO) bin xsim.bat]

# xsim.bat splits arguments on '=' so plusargs go through a file,
# read back because a fresh file can come out empty on windows
proc write_args {path text} {
    for {set i 0} {$i < 5} {incr i} {
        set fh [open $path w]
        puts $fh $text
        close $fh
        if {[file size $path] > 0} { return }
        after 200
    }
    error "could not write $path"
}
set results {}
set failures 0

foreach bench $benches {
    if {[llength [bench_sources $bench]] == 0} {
        puts "skipping $bench, bench not written yet"
        continue
    }

    # compile and elaborate once, then only xsim runs per test and seed
    make_project $bench
    launch_simulation -scripts_only
    set dir [xsim_dir $bench]
    cd $dir
    if {[catch {exec cmd /c [file nativename [file join $dir compile.bat]]} msg]
        || [catch {exec cmd /c [file nativename [file join $dir elaborate.bat]]} msg]} {
        puts "FAIL $bench does not build, see $dir"
        lappend results [list $bench build - -1 -1 ""]
        incr failures
        close_project
        continue
    }

    foreach test [dict get $regress_tests $bench] {
        foreach seed $seeds {
            set args [file join $dir ${test}_$seed.args]
            write_args $args [plusargs $test $seed UVM_LOW]
            set log [file join $dir ${test}_$seed.log]
            catch {exec cmd /c [file nativename $xsim] tb_${bench}_behav -R \
                       -f [file nativename $args] -log [file nativename $log]}
            lassign [uvm_result $log] errors fatals coverage
            if {$errors != 0 || $fatals != 0} { incr failures }
            lappend results [list $bench $test $seed $errors $fatals $coverage]
            puts [format "%-4s %-24s seed %-4s err %s" \
                      [expr {$errors == 0 && $fatals == 0 ? "PASS" : "FAIL"}] $test $seed $errors]
        }
    }
    close_project
}

puts ""
puts "[llength $results] runs, $failures failed"
exit [expr {$failures == 0 ? 0 : 1}]
