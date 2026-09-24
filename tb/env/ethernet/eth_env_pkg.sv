package eth_env_pkg;
    import uvm_pkg::*;
    `include "uvm_macros.svh"
    import tb_utils_pkg::*;
    import gmii_pkg::*;

    // toolchain and wiring check, no dut traffic
    class hello_test extends uvm_test;
        `uvm_component_utils(hello_test)

        virtual gmii_if gmii;
        virtual eth_out_if out;

        function new(string name, uvm_component parent);
            super.new(name, parent);
        endfunction

        function void build_phase(uvm_phase phase);
            super.build_phase(phase);
            if (!uvm_config_db #(virtual gmii_if)::get(this, "env.agent", "vif", gmii)) begin
                `uvm_fatal("NOVIF", "gmii_if not set")
            end
            if (!uvm_config_db #(virtual eth_out_if)::get(this, "env.out_mon", "vif", out)) begin
                `uvm_fatal("NOVIF", "eth_out_if not set")
            end
        endfunction

        task run_phase(uvm_phase phase);
            phase.raise_objection(this);
            wait (gmii.rst === 1'b0);
            `uvm_info("HELLO", "hello from the ethernet bench, reset released", UVM_LOW)
            #100ns;
            phase.drop_objection(this);
        endtask
    endclass
    // randomizes a few frames and checks the fcs they carry
    class item_test extends uvm_test;
        `uvm_component_utils(item_test)

        function new(string name, uvm_component parent);
            super.new(name, parent);
        endfunction

        task run_phase(uvm_phase phase);
            eth_frame_item t;
            bytes_t b;
            phase.raise_objection(this);
            repeat (5) begin
                t = eth_frame_item::type_id::create("t");
                if (!t.randomize() with { payload_len inside {[46:64]}; })
                    `uvm_fatal("RAND", "frame randomize failed")
                b = t.frame_bytes();
                `uvm_info("ITEM", $sformatf("%s fcs_ok %0b: %s", t.convert2string(),
                          fcs_ok(b), hex(b, 24)), UVM_LOW)
            end
            phase.drop_objection(this);
        endtask
    endclass
endpackage
