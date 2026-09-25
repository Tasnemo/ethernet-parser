package eth_env_pkg;
    import uvm_pkg::*;
    `include "uvm_macros.svh"
    import tb_utils_pkg::*;
    import gmii_pkg::*;

    // ethernet parser limits
    localparam int MAX_PAYLOAD = 1500;
    localparam int MIN_COUNT   = 50;   // 46 payload + 4 fcs
    localparam int MAX_COUNT   = 1504; // 1500 payload + 4 fcs

    // what the parser put out for one frame
    class eth_out_item extends out_item;
        `uvm_object_utils(eth_out_item)

        bytes_t bytes;
        bit error;
        bit fcs_error;

        function new(string name = "eth_out_item");
            super.new(name);
        endfunction

        function bit check(out_item act, output string why);
            eth_out_item a;
            if (!$cast(a, act)) begin
                why = "wrong item type";
                return 0;
            end
            if (a.error != error) begin
                why = "ether_error";
                return 0;
            end
            if (a.fcs_error != fcs_error) begin
                why = "fcs_error";
                return 0;
            end
            // bytes before an error are speculative
            if (error ? !prefix_of(a.bytes, bytes) : (a.bytes != bytes)) begin
                why = "payload bytes";
                return 0;
            end
            return 1;
        endfunction

        function string convert2string();
            return $sformatf("err %0b fcs_err %0b %s", error, fcs_error, hex(bytes));
        endfunction
    endclass

    // collects payload bytes and takes the verdict on end_of_packet
    class eth_out_monitor extends uvm_monitor;
        `uvm_component_utils(eth_out_monitor)

        virtual eth_out_if vif;
        uvm_analysis_port #(out_item) ap;

        function new(string name, uvm_component parent);
            super.new(name, parent);
        endfunction

        function void build_phase(uvm_phase phase);
            super.build_phase(phase);
            ap = new("ap", this);
            if (!uvm_config_db #(virtual eth_out_if)::get(this, "", "vif", vif)) begin
                `uvm_fatal("NOVIF", "eth_out_if not set")
            end
        endfunction

        task run_phase(uvm_phase phase);
            eth_out_item t;
            bytes_t bytes;
            forever begin
                @(vif.mon_cb);
                if (vif.mon_cb.payload_ether_valid) bytes.push_back(vif.mon_cb.o_stream);
                if (vif.mon_cb.end_of_packet) begin
                    t = eth_out_item::type_id::create("t");
                    t.bytes     = bytes;
                    t.error     = vif.mon_cb.ether_error;
                    t.fcs_error = vif.mon_cb.fcs_error;
                    `uvm_info("OUTMON", t.convert2string(), UVM_MEDIUM)
                    ap.write(t);
                    bytes.delete();
                end
            end
        endtask
    endclass

    // predicts the parser output from the bytes on the wire
    class eth_ref_model extends uvm_subscriber #(gmii_obs_item);
        `uvm_component_utils(eth_ref_model)

        uvm_analysis_port #(out_item) ap;

        function new(string name, uvm_component parent);
            super.new(name, parent);
        endfunction

        function void build_phase(uvm_phase phase);
            super.build_phase(phase);
            ap = new("ap", this);
        endfunction

        static function eth_out_item predict(bytes_t b, bit rx_er);
            eth_out_item e = eth_out_item::type_id::create("exp");
            int count = b.size() - 14; // payload plus fcs
            int keep;

            // no fcs compare on a runt or an over length frame
            e.fcs_error = (count >= MIN_COUNT) && (count <= MAX_COUNT) && !fcs_ok(b);
            e.error = rx_er || (count - 4 < MIN_COUNT) || (count > MAX_COUNT) || e.fcs_error;

            // payload is capped and the last 4 bytes stay in the fcs pipe
            keep = count - 4;
            if (keep > MAX_PAYLOAD) keep = MAX_PAYLOAD;
            for (int i = 0; i < keep; i++) e.bytes.push_back(b[14 + i]);
            return e;
        endfunction

        function void write(gmii_obs_item t);
            ap.write(predict(t.bytes, t.rx_er));
        endfunction
    endclass

    class eth_env extends uvm_env;
        `uvm_component_utils(eth_env)

        gmii_agent agent;
        eth_out_monitor out_mon;
        eth_ref_model ref_model;
        out_scoreboard scb;

        function new(string name, uvm_component parent);
            super.new(name, parent);
        endfunction

        function void build_phase(uvm_phase phase);
            super.build_phase(phase);
            agent     = gmii_agent::type_id::create("agent", this);
            out_mon   = eth_out_monitor::type_id::create("out_mon", this);
            ref_model = eth_ref_model::type_id::create("ref_model", this);
            scb       = out_scoreboard::type_id::create("scb", this);
        endfunction

        function void connect_phase(uvm_phase phase);
            agent.mon.ap.connect(ref_model.analysis_export);
            ref_model.ap.connect(scb.exp_fifo.analysis_export);
            out_mon.ap.connect(scb.act_fifo.analysis_export);
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
