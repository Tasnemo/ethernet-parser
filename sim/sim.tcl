# build a vivado project for one uvm bench and run it on xsim
# batch: vivado -mode batch -notrace -source sim/sim.tcl -tclargs ethernet hello_test [seed] [verbosity]
# gui:   set argv {ethernet hello_test}; source sim/sim.tcl

set bench     [lindex $argv 0]
set test      [lindex $argv 1]
set seed      1
set verbosity UVM_MEDIUM
if {[llength $argv] > 2} { set seed      [lindex $argv 2] }
if {[llength $argv] > 3} { set verbosity [lindex $argv 3] }

set root [file normalize [file join [file dirname [info script]] ..]]

# compile order matters, packages before the files that import them
set common {tb/common/tb_utils_pkg.sv}
set gmii   {tb/agents/gmii/gmii_if.sv tb/agents/gmii/gmii_pkg.sv}
set stream {tb/agents/stream/stream_if.sv tb/agents/stream/stream_pkg.sv}

set eth_env  {tb/env/ethernet/eth_out_if.sv tb/env/ethernet/eth_env_pkg.sv}
set ipv4_env {tb/env/ipv4/ipv4_out_if.sv tb/env/ipv4/ipv4_env_pkg.sv}
set udp_env  {tb/env/udp/udp_out_if.sv tb/env/udp/udp_env_pkg.sv}

# the top bench reuses the block envs for its reference model
set bench_files [dict create \
    ethernet [concat src/ethernet_parser.sv $common $gmii $eth_env \
                  tb/env/ethernet/tb_ethernet.sv] \
    ipv4     [concat src/ipv4_parser.sv $common $stream $ipv4_env \
                  tb/env/ipv4/tb_ipv4.sv] \
    udp      [concat src/udp_parser.sv $common $stream $udp_env \
                  tb/env/udp/tb_udp.sv] \
    top      [concat src/ethernet_parser.sv src/ipv4_parser.sv src/udp_parser.sv \
                  src/ether_ipv4_udp_top_level.sv $common $gmii $stream \
                  $eth_env $ipv4_env $udp_env \
                  tb/env/top/parser_if.sv tb/env/top/top_env_pkg.sv tb/env/top/tb_top.sv]]

if {![dict exists $bench_files $bench]} {
    puts "usage: -tclargs ethernet|ipv4|udp|top <test> \[seed\] \[verbosity\]"
    exit 1
}

# files not written yet are skipped so this works while tb/ is being built
set files {}
foreach f [dict get $bench_files $bench] {
    set path [file join $root $f]
    if {[file exists $path]} { lappend files $path }
}
set top tb_$bench
if {[lsearch -glob $files "*/$top.sv"] < 0} {
    puts "missing tb/env/$bench/$top.sv, nothing to run"
    exit 1
}

# fresh project every run, same part as the synthesis numbers
set work [file join $root sim work $bench]
create_project $bench $work -part xc7a35ticsg324-1L -force
set_property source_mgmt_mode None [current_project]
add_files -fileset sim_1 -norecurse $files
set_property file_type SystemVerilog [get_files -of_objects [get_filesets sim_1]]

set sim [get_filesets sim_1]
set_property top $top $sim
set_property top_lib xil_defaultlib $sim
set_property -name xsim.compile.xvlog.more_options -value {-L uvm} -objects $sim
set_property -name xsim.elaborate.xelab.more_options -value {-L uvm} -objects $sim
set plusargs "-testplusarg UVM_VERBOSITY=$verbosity -sv_seed $seed"
if {$test ne ""} { append plusargs " -testplusarg UVM_TESTNAME=$test" }
set_property -name xsim.simulate.xsim.more_options -value $plusargs -objects $sim
set_property -name xsim.simulate.runtime -value all -objects $sim

launch_simulation

# gui keeps the project and waveform open
if {[info exists rdi::mode] && $rdi::mode eq "gui"} { return }

# uvm report summary decides pass or fail
set log [file join $work $bench.sim sim_1 behav xsim simulate.log]
set text ""
if {[file exists $log]} {
    set fh [open $log r]
    set text [read $fh]
    close $fh
}
close_sim -quiet

set errors -1
set fatals -1
regexp {UVM_ERROR\s*:\s*(\d+)} $text -> errors
regexp {UVM_FATAL\s*:\s*(\d+)} $text -> fatals
if {$errors == 0 && $fatals == 0} {
    puts "PASS $top $test seed=$seed"
    exit 0
}
if {$errors < 0} {
    puts "FAIL $top $test seed=$seed (no uvm report summary, see $log)"
} else {
    puts "FAIL $top $test seed=$seed (UVM_ERROR $errors, UVM_FATAL $fatals)"
}
exit 1
