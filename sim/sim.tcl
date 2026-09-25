# build a vivado project for one uvm bench and run one test on xsim
# batch: vivado -mode batch -notrace -source sim/sim.tcl -tclargs ethernet eth_smoke_test [seed] [verbosity]
# gui:   set argv {ethernet eth_smoke_test}; source sim/sim.tcl

source -notrace [file join [file dirname [info script]] sim_lib.tcl]

set bench     [lindex $argv 0]
set test      [lindex $argv 1]
set seed      1
set verbosity UVM_MEDIUM
if {[llength $argv] > 2} { set seed      [lindex $argv 2] }
if {[llength $argv] > 3} { set verbosity [lindex $argv 3] }

if {![dict exists $bench_files $bench]} {
    puts "usage: -tclargs ethernet|ipv4|udp|top <test> \[seed\] \[verbosity\]"
    exit 1
}
if {[llength [bench_sources $bench]] == 0} {
    puts "missing tb/env/$bench/tb_$bench.sv, nothing to run"
    exit 1
}

make_project $bench
set_property -name xsim.simulate.xsim.more_options -value [plusargs $test $seed $verbosity] \
    -objects [get_filesets sim_1]
launch_simulation

# gui keeps the project and waveform open
if {[info exists rdi::mode] && $rdi::mode eq "gui"} { return }

set log [file join [xsim_dir $bench] simulate.log]
close_sim -quiet
lassign [uvm_result $log] errors fatals coverage
if {$errors == 0 && $fatals == 0} {
    puts "PASS tb_$bench $test seed=$seed $coverage"
    exit 0
}
if {$errors < 0} {
    puts "FAIL tb_$bench $test seed=$seed (no uvm report summary, see $log)"
} else {
    puts "FAIL tb_$bench $test seed=$seed (UVM_ERROR $errors, UVM_FATAL $fatals)"
}
exit 1
