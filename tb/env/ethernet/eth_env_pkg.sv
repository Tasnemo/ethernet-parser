package eth_env_pkg;
    import uvm_pkg::*;
    `include "uvm_macros.svh"

    // toolchain check, no dut traffic
    class hello_test extends uvm_test;
        `uvm_component_utils(hello_test)

        function new(string name, uvm_component parent);
            super.new(name, parent);
        endfunction

        task run_phase(uvm_phase phase);
            phase.raise_objection(this);
            #100ns;
            `uvm_info("HELLO", "hello from the ethernet bench", UVM_LOW)
            phase.drop_objection(this);
        endtask
    endclass

endpackage