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
            e.error = rx_er || (count < MIN_COUNT) || (count > MAX_COUNT) || e.fcs_error;

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

    class eth_coverage extends uvm_subscriber #(gmii_obs_item);
        `uvm_component_utils(eth_coverage)

        int payload_len;
        bit rx_er;
        bit fcs_good;

        covergroup cg;
            cp_len: coverpoint payload_len {
                bins header_cut = {[-18:-1]};
                bins runt       = {[0:45]};
                bins minimum    = {46};
                bins short_len  = {[47:127]};
                bins mid_len    = {[128:1023]};
                bins long_len   = {[1024:1499]};
                bins maximum    = {1500};
                bins oversize   = {[1501:$]};
            }
            cp_rx_er: coverpoint rx_er;
            cp_fcs: coverpoint fcs_good;
            x_len_fcs: cross cp_len, cp_fcs {
                ignore_bins cut = binsof(cp_len.header_cut);
            }
        endgroup

        function new(string name, uvm_component parent);
            super.new(name, parent);
            cg = new();
        endfunction

        function void write(gmii_obs_item t);
            payload_len = t.bytes.size() - 18;
            rx_er = t.rx_er;
            fcs_good = fcs_ok(t.bytes);
            cg.sample();
        endfunction

        function void report_phase(uvm_phase phase);
            `uvm_info("COV", $sformatf("ethernet coverage %0.1f%%", cg.get_coverage()), UVM_LOW)
        endfunction
    endclass

    class eth_env extends uvm_env;
        `uvm_component_utils(eth_env)

        gmii_agent agent;
        eth_out_monitor out_mon;
        eth_ref_model ref_model;
        out_scoreboard scb;
        eth_coverage cov;

        function new(string name, uvm_component parent);
            super.new(name, parent);
        endfunction

        function void build_phase(uvm_phase phase);
            super.build_phase(phase);
            agent     = gmii_agent::type_id::create("agent", this);
            out_mon   = eth_out_monitor::type_id::create("out_mon", this);
            ref_model = eth_ref_model::type_id::create("ref_model", this);
            scb       = out_scoreboard::type_id::create("scb", this);
            cov       = eth_coverage::type_id::create("cov", this);
        endfunction

        function void connect_phase(uvm_phase phase);
            agent.mon.ap.connect(ref_model.analysis_export);
            agent.mon.ap.connect(cov.analysis_export);
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

    // one of each error in turn
    class eth_error_seq extends gmii_base_seq;
        `uvm_object_utils(eth_error_seq)

        function new(string name = "eth_error_seq");
            super.new(name);
        endfunction

        function void shape(eth_frame_item t, int unsigned i);
            bit ok;
            case (i % 5)
                0: ok = t.randomize() with { payload_len inside {[1:45]}; };
                1: ok = t.randomize() with { payload_len inside {[1501:1520]}; };
                2: ok = t.randomize() with { payload_len inside {[46:128]}; corrupt_fcs == 1; };
                3: ok = t.randomize() with { payload_len inside {[46:128]};
                                              rx_er_at inside {[0:payload_len + 17]}; };
                4: ok = t.randomize() with { payload_len inside {[46:128]};
                                              truncate_at inside {[1:payload_len + 17]}; };
            endcase
            if (!ok) `uvm_fatal("RAND", "frame randomize failed")
        endfunction
    endclass

    // payload sizes right around the runt and max limits
    class eth_boundary_seq extends gmii_base_seq;
        `uvm_object_utils(eth_boundary_seq)

        int sizes[] = '{44, 45, 46, 47, 48, 49, 50, 1499, 1500, 1501};

        function new(string name = "eth_boundary_seq");
            super.new(name);
            count = sizes.size();
        endfunction

        function void shape(eth_frame_item t, int unsigned i);
            if (!t.randomize() with { payload_len == local::sizes[i]; })
                `uvm_fatal("RAND", "frame randomize failed")
        endfunction
    endclass

    // 802.3 asks for 12 idle cycles, the parser needs 4 to flush its delay line
    class eth_back_to_back_seq extends eth_good_seq;
        `uvm_object_utils(eth_back_to_back_seq)

        function new(string name = "eth_back_to_back_seq");
            super.new(name);
        endfunction

        function void shape(eth_frame_item t, int unsigned i);
            t.c_gap.constraint_mode(0);
            if (!t.randomize() with { payload_len inside {[46:96]}; gap inside {[4:12]}; })
                `uvm_fatal("RAND", "frame randomize failed")
        endfunction
    endclass

    // mostly good frames with every error mixed in
    class eth_random_seq extends gmii_base_seq;
        `uvm_object_utils(eth_random_seq)

        function new(string name = "eth_random_seq");
            super.new(name);
        endfunction

        function void shape(eth_frame_item t, int unsigned i);
            int kind;
            bit ok;
            kind = $urandom_range(0, 9);
            case (kind)
                0: ok = t.randomize() with { payload_len inside {[0:45]}; };
                1: ok = t.randomize() with { payload_len inside {[1501:1510]}; };
                2: ok = t.randomize() with { payload_len inside {[46:200]}; corrupt_fcs == 1; };
                3: ok = t.randomize() with { payload_len inside {[46:200]};
                                              rx_er_at inside {[0:payload_len + 17]}; };
                4: ok = t.randomize() with { payload_len inside {[46:200]};
                                              truncate_at inside {[1:payload_len + 17]}; };
                default: ok = t.randomize() with {
                    payload_len dist {[46:200] :/ 8, [201:1500] :/ 2}; };
            endcase
            if (!ok) `uvm_fatal("RAND", "frame randomize failed")
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

    class eth_error_test extends eth_base_test;
        `uvm_component_utils(eth_error_test)

        function new(string name, uvm_component parent);
            super.new(name, parent);
        endfunction

        function gmii_base_seq make_seq();
            eth_error_seq s = eth_error_seq::type_id::create("seq");
            s.count = 25;
            return s;
        endfunction
    endclass

    class eth_boundary_test extends eth_base_test;
        `uvm_component_utils(eth_boundary_test)

        function new(string name, uvm_component parent);
            super.new(name, parent);
        endfunction

        function gmii_base_seq make_seq();
            eth_boundary_seq s = eth_boundary_seq::type_id::create("seq");
            return s;
        endfunction
    endclass

    class eth_back_to_back_test extends eth_base_test;
        `uvm_component_utils(eth_back_to_back_test)

        function new(string name, uvm_component parent);
            super.new(name, parent);
        endfunction

        function gmii_base_seq make_seq();
            eth_back_to_back_seq s = eth_back_to_back_seq::type_id::create("seq");
            s.count = 20;
            return s;
        endfunction
    endclass

    class eth_random_test extends eth_base_test;
        `uvm_component_utils(eth_random_test)

        function new(string name, uvm_component parent);
            super.new(name, parent);
        endfunction

        function gmii_base_seq make_seq();
            eth_random_seq s = eth_random_seq::type_id::create("seq");
            s.count = 200;
            return s;
        endfunction
    endclass

endpackage
