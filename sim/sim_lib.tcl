# shared project setup for sim.tcl and regress.tcl

set sim_root [file normalize [file join [file dirname [info script]] ..]]

# compile order matters, packages before the files that import them
set common   {tb/common/tb_utils_pkg.sv}
set gmii     {tb/agents/gmii/gmii_if.sv tb/agents/gmii/gmii_pkg.sv}
set stream   {tb/agents/stream/stream_if.sv tb/agents/stream/stream_pkg.sv}
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

# existing files for a bench, empty when its tb module is not written yet
proc bench_sources {bench} {
    global sim_root bench_files
    set files {}
    foreach f [dict get $bench_files $bench] {
        set path [file join $sim_root $f]
        if {[file exists $path]} { lappend files $path }
    }
    if {[lsearch -glob $files "*/tb_$bench.sv"] < 0} { return {} }
    return $files
}

# fresh project every run, same part as the synthesis numbers
proc make_project {bench} {
    global sim_root
    set work [file join $sim_root sim work $bench]
    create_project $bench $work -part xc7a35ticsg324-1L -force
    set_property source_mgmt_mode None [current_project]
    add_files -fileset sim_1 -norecurse [bench_sources $bench]
    set_property file_type SystemVerilog [get_files -of_objects [get_filesets sim_1]]

    set sim [get_filesets sim_1]
    set_property top tb_$bench $sim
    set_property top_lib xil_defaultlib $sim
    set_property -name xsim.compile.xvlog.more_options -value {-L uvm} -objects $sim
    set_property -name xsim.elaborate.xelab.more_options -value {-L uvm} -objects $sim
    set_property -name xsim.simulate.runtime -value all -objects $sim
    return $work
}

proc plusargs {test seed verbosity} {
    set args "-testplusarg UVM_VERBOSITY=$verbosity -sv_seed $seed"
    if {$test ne ""} { append args " -testplusarg UVM_TESTNAME=$test" }
    return $args
}

proc xsim_dir {bench} {
    global sim_root
    return [file join $sim_root sim work $bench $bench.sim sim_1 behav xsim]
}

# uvm report summary, -1 when the run never got that far
proc uvm_result {log} {
    set errors -1
    set fatals -1
    set coverage ""
    if {[file exists $log]} {
        set fh [open $log r]
        set text [read $fh]
        close $fh
        regexp {UVM_ERROR\s*:\s*(\d+)} $text -> errors
        regexp {UVM_FATAL\s*:\s*(\d+)} $text -> fatals
        regexp {coverage ([0-9.]+%)} $text -> coverage
    }
    return [list $errors $fatals $coverage]
}
