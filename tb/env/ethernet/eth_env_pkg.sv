package eth_env_pkg;
    import uvm_pkg::*;
    `include "uvm_macros.svh"
    import tb_utils_pkg::*;
    import gmii_pkg::*;


    class eth_env extends uvm_env;
        `uvm_component_utils(eth_env)

        gmii_agent agent;

        function new(string name, uvm_component parent);
            super.new(name, parent);
        endfunction

        function void build_phase(uvm_phase phase);
            super.build_phase(phase);
            agent = gmii_agent::type_id::create("agent", this);
        endfunction
    endclass

    // good frames clear of the runt limit, small payloads keep runs short
    class eth_good_seq extends gmii_base_seq;
        `uvm_object_utils(eth_good_seq)

        function new(string name = "eth_good_seq");
            super.new(name);
        endfunction

        function void shape(eth_frame_item t, int unsigned i);
            if (!t.randomize() with { payload_len dist {[64:128] :/ 8, [129:1500] :/ 2}; })
                `uvm_fatal("RAND", "frame randomize failed")
        endfunction
    endclass

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

    // builds the env and runs whatever sequence the subclass picks
    class eth_base_test extends uvm_test;
        `uvm_component_utils(eth_base_test)

        eth_env env;

        function new(string name, uvm_component parent);
            super.new(name, parent);
        endfunction

        function void build_phase(uvm_phase phase);
            super.build_phase(phase);
            env = eth_env::type_id::create("env", this);
        endfunction

        virtual function gmii_base_seq make_seq();
            eth_good_seq s = eth_good_seq::type_id::create("seq");
            return s;
        endfunction

        task run_phase(uvm_phase phase);
            gmii_base_seq s;
            phase.raise_objection(this);
            s = make_seq();
            s.start(env.agent.sqr);
            // let the last frame drain through the parser
            #1us;
            phase.drop_objection(this);
        endtask
    endclass

    class eth_smoke_test extends eth_base_test;
        `uvm_component_utils(eth_smoke_test)

        function new(string name, uvm_component parent);
            super.new(name, parent);
        endfunction
    endclass

endpackage
