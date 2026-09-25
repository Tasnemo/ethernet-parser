package top_env_pkg;
    import uvm_pkg::*;
    `include "uvm_macros.svh"
    import tb_utils_pkg::*;
    import gmii_pkg::*;
    import eth_env_pkg::*;
    import ipv4_env_pkg::*;
    import udp_env_pkg::*;

    // udp payload out of the full stack for one frame
    class top_out_item extends out_item;
        `uvm_object_utils(top_out_item)

        bytes_t bytes;
        bit error;
        int start_count;
        int start_pos = -1;
        int last_count;
        int last_pos = -1;

        function new(string name = "top_out_item");
            super.new(name);
        endfunction

        function bit check(out_item act, output string why);
            top_out_item a;
            if (!$cast(a, act)) begin
                why = "wrong item type";
                return 0;
            end
            if (a.error != error) begin
                why = "parser_error";
                return 0;
            end
            if (error) begin
                if (!prefix_of(a.bytes, bytes)) begin
                    why = "speculative bytes are not a prefix";
                    return 0;
                end
                return 1;
            end
            if (a.bytes != bytes) begin
                why = "parser bytes";
                return 0;
            end
            if (a.start_count != start_count || a.start_pos != start_pos) begin
                why = "parser_start";
                return 0;
            end
            if (a.last_count != last_count || a.last_pos != last_pos) begin
                why = "parser_last";
                return 0;
            end
            return 1;
        endfunction

        function string convert2string();
            return $sformatf("err %0b start %0d@%0d last %0d@%0d %s",
                             error, start_count, start_pos, last_count, last_pos, hex(bytes));
        endfunction
    endclass

    // one item per frame, from rx_dv high until the end_of_packet cycle
    class top_out_monitor extends uvm_monitor;
        `uvm_component_utils(top_out_monitor)

        virtual parser_if vif;
        uvm_analysis_port #(out_item) ap;

        function new(string name, uvm_component parent);
            super.new(name, parent);
        endfunction

        function void build_phase(uvm_phase phase);
            super.build_phase(phase);
            ap = new("ap", this);
            if (!uvm_config_db #(virtual parser_if)::get(this, "", "vif", vif)) begin
                `uvm_fatal("NOVIF", "parser_if not set")
            end
        endfunction

        task run_phase(uvm_phase phase);
            top_out_item t;
            bit prev_dv;
            forever begin
                @(vif.mon_cb);
                if (t == null && vif.mon_cb.frame_dv) t = top_out_item::type_id::create("t");
                if (t != null) begin
                    if (vif.mon_cb.parser_start) begin
                        t.start_count++;
                        t.start_pos = t.bytes.size();
                    end
                    if (vif.mon_cb.parser_last) begin
                        t.last_count++;
                        t.last_pos = t.bytes.size();
                    end
                    if (vif.mon_cb.parser_valid) t.bytes.push_back(vif.mon_cb.parser);
                    if (vif.mon_cb.parser_error) t.error = 1;
                    // the cycle after rx_dv drops carries end_of_packet
                    if (prev_dv && !vif.mon_cb.frame_dv) begin
                        `uvm_info("OUTMON", t.convert2string(), UVM_MEDIUM)
                        ap.write(t);
                        t = null;
                    end
                end
                prev_dv = vif.mon_cb.frame_dv;
            end
        endtask
    endclass

    // chains the block reference models the same way the top level wires the parsers
    class top_ref_model extends uvm_subscriber #(gmii_obs_item);
        `uvm_component_utils(top_ref_model)

        uvm_analysis_port #(out_item) ap;

        function new(string name, uvm_component parent);
            super.new(name, parent);
        endfunction

        function void build_phase(uvm_phase phase);
            super.build_phase(phase);
            ap = new("ap", this);
        endfunction

        static function top_out_item predict(bytes_t frame, bit rx_er);
            top_out_item e = top_out_item::type_id::create("exp");
            eth_out_item eth;
            ipv4_out_item ip;
            udp_out_item udp;
            bytes_t pkt;
            bytes_t pseudo;
            bytes_t seg;
            int total;

            eth = eth_ref_model::predict(frame, rx_er);
            e.error = eth.error;

            // ethertype 0x0800 routes the ethernet payload into ipv4
            if (frame.size() >= 14 && be16(frame, 12) == 16'h0800 && eth.bytes.size() > 0) begin
                pkt = eth.bytes;
                ip = ipv4_ref_model::predict(pkt, 0);
                e.error |= ip.error;

                // protocol 17 routes the ipv4 payload into udp
                if (pkt.size() >= 20 && pkt[9] == 8'd17) begin
                    total = be16(pkt, 2);
                    for (int i = 20; i < total && i < pkt.size(); i++) seg.push_back(pkt[i]);
                    if (seg.size() > 0) begin
                        pseudo = pkt[12:19];
                        udp = udp_ref_model::predict(pseudo, seg,
                                                     (total <= pkt.size()) ? total - 21 : -1, 0);
                        e.error |= udp.error;
                        e.bytes = udp.bytes;
                    end
                end
            end

            if (e.bytes.size() > 0) begin
                e.start_count = 1;
                e.start_pos = 0;
                e.last_count = 1;
                e.last_pos = e.bytes.size() - 1;
            end
            return e;
        endfunction

        function void write(gmii_obs_item t);
            ap.write(predict(t.bytes, t.rx_er));
        endfunction
    endclass

    class top_coverage extends uvm_subscriber #(gmii_obs_item);
        `uvm_component_utils(top_coverage)

        bit is_ipv4;
        bit is_udp;
        bit has_payload;
        bit err;

        covergroup cg;
            cp_ipv4: coverpoint is_ipv4;
            cp_udp: coverpoint is_udp;
            cp_payload: coverpoint has_payload;
            cp_err: coverpoint err;
            x_route_err: cross cp_ipv4, cp_udp, cp_err {
                ignore_bins udp_needs_ipv4 = binsof(cp_ipv4) intersect {0} && binsof(cp_udp) intersect {1};
            }
        endgroup

        function new(string name, uvm_component parent);
            super.new(name, parent);
            cg = new();
        endfunction

        function void write(gmii_obs_item t);
            top_out_item e = top_ref_model::predict(t.bytes, t.rx_er);
            is_ipv4 = (t.bytes.size() >= 14) && (be16(t.bytes, 12) == 16'h0800);
            is_udp = is_ipv4 && (t.bytes.size() >= 24) && (t.bytes[23] == 8'd17);
            has_payload = e.bytes.size() > 0;
            err = e.error;
            cg.sample();
        endfunction

        function void report_phase(uvm_phase phase);
            `uvm_info("COV", $sformatf("top coverage %0.1f%%", cg.get_coverage()), UVM_LOW)
        endfunction
    endclass

    class top_env extends uvm_env;
        `uvm_component_utils(top_env)

        gmii_agent agent;
        top_out_monitor out_mon;
        top_ref_model ref_model;
        out_scoreboard scb;
        top_coverage cov;

        function new(string name, uvm_component parent);
            super.new(name, parent);
        endfunction

        function void build_phase(uvm_phase phase);
            super.build_phase(phase);
            agent     = gmii_agent::type_id::create("agent", this);
            out_mon   = top_out_monitor::type_id::create("out_mon", this);
            ref_model = top_ref_model::type_id::create("ref_model", this);
            scb       = out_scoreboard::type_id::create("scb", this);
            cov       = top_coverage::type_id::create("cov", this);
        endfunction

        function void connect_phase(uvm_phase phase);
            agent.mon.ap.connect(ref_model.analysis_export);
            agent.mon.ap.connect(cov.analysis_export);
            ref_model.ap.connect(scb.exp_fifo.analysis_export);
            out_mon.ap.connect(scb.act_fifo.analysis_export);
        endfunction
    endclass

    typedef enum {
        GOOD_UDP, BAD_UDP_CHECKSUM, ZERO_UDP_CHECKSUM, UDP_PORT_ZERO,
        BAD_IPV4_CHECKSUM, IPV4_FRAGMENT, NOT_UDP, NOT_IPV4,
        BAD_FCS, RX_ERROR, TRUNCATED
    } frame_kind_e;

    // builds eth/ipv4/udp frames layer by layer with the block items
    class top_base_seq extends gmii_base_seq;
        `uvm_object_utils(top_base_seq)

        function new(string name = "top_base_seq");
            super.new(name);
        endfunction

        virtual function frame_kind_e pick(int unsigned i);
            return GOOD_UDP;
        endfunction

        function void build(eth_frame_item t, frame_kind_e kind, int udp_payload = -1);
            udp_seg_item u = udp_seg_item::type_id::create("u");
            ipv4_pkt_item p = ipv4_pkt_item::type_id::create("p");
            bytes_t seg;
            bytes_t pkt;

            if (!t.randomize() with { payload_len == 0; }) `uvm_fatal("RAND", "frame randomize failed")
            if (!u.randomize()) `uvm_fatal("RAND", "udp randomize failed")
            if (!p.randomize()) `uvm_fatal("RAND", "ipv4 randomize failed")

            if (udp_payload >= 0) begin
                u.payload = new[udp_payload];
                foreach (u.payload[i]) u.payload[i] = 8'(i * 7 + 3);
                u.payload_len = udp_payload;
            end
            u.src_ip = p.src;
            u.dst_ip = p.dst;
            case (kind)
                BAD_UDP_CHECKSUM:  u.bad_checksum = 1;
                ZERO_UDP_CHECKSUM: u.zero_checksum = 1;
                UDP_PORT_ZERO:     u.dst_port = 0;
                default: ;
            endcase
            seg = u.to_bytes();

            p.protocol = (kind == NOT_UDP) ? 8'd6 : 8'd17;
            p.payload = new[seg.size()];
            foreach (seg[i]) p.payload[i] = seg[i];
            p.payload_len = seg.size();
            p.total_len = 20 + seg.size();
            p.pad = 0;
            case (kind)
                BAD_IPV4_CHECKSUM: p.bad_checksum = 1;
                IPV4_FRAGMENT:     p.mf = 1;
                default: ;
            endcase
            pkt = p.to_bytes();

            // short packets get ethernet padding up to 46 bytes
            while (pkt.size() < 46) pkt.push_back(8'h00);
            t.payload = new[pkt.size()];
            foreach (pkt[i]) t.payload[i] = pkt[i];
            t.payload_len = pkt.size();
            t.ethertype = (kind == NOT_IPV4) ? (($urandom_range(0, 1)) ? 16'h86DD : 16'h0806)
                                             : 16'h0800;
            case (kind)
                BAD_FCS:   t.corrupt_fcs = 1;
                RX_ERROR:  t.rx_er_at = $urandom_range(0, pkt.size() + 17);
                TRUNCATED: t.truncate_at = $urandom_range(1, pkt.size() + 17);
                default: ;
            endcase
            `uvm_info("SEQ", $sformatf("%s: %s", kind.name(), u.convert2string()), UVM_HIGH)
        endfunction

        function void shape(eth_frame_item t, int unsigned i);
            build(t, pick(i));
        endfunction
    endclass

    // every frame kind in turn
    class top_error_seq extends top_base_seq;
        `uvm_object_utils(top_error_seq)

        function new(string name = "top_error_seq");
            super.new(name);
        endfunction

        function frame_kind_e pick(int unsigned i);
            return frame_kind_e'(i % (TRUNCATED + 1));
        endfunction
    endclass

    // mostly good udp with every other kind mixed in
    class top_mixed_seq extends top_base_seq;
        `uvm_object_utils(top_mixed_seq)

        function new(string name = "top_mixed_seq");
            super.new(name);
        endfunction

        function frame_kind_e pick(int unsigned i);
            if ($urandom_range(0, 9) < 4) return GOOD_UDP;
            return frame_kind_e'($urandom_range(0, TRUNCATED));
        endfunction
    endclass

    // the hand picked cases from the first standalone bench
    class top_directed_seq extends top_base_seq;
        `uvm_object_utils(top_directed_seq)

        frame_kind_e kinds[] = '{GOOD_UDP, GOOD_UDP, GOOD_UDP, ZERO_UDP_CHECKSUM,
                                 BAD_UDP_CHECKSUM, NOT_UDP, GOOD_UDP};
        int sizes[] = '{30, 5, 17, 30, 30, 30, 30};

        function new(string name = "top_directed_seq");
            super.new(name);
            count = kinds.size();
        endfunction

        function void shape(eth_frame_item t, int unsigned i);
            build(t, kinds[i], sizes[i]);
        endfunction
    endclass

    class top_base_test extends uvm_test;
        `uvm_component_utils(top_base_test)

        top_env env;

        function new(string name, uvm_component parent);
            super.new(name, parent);
        endfunction

        function void build_phase(uvm_phase phase);
            super.build_phase(phase);
            env = top_env::type_id::create("env", this);
        endfunction

        virtual function gmii_base_seq make_seq();
            top_base_seq s = top_base_seq::type_id::create("seq");
            s.count = 20;
            return s;
        endfunction

        task run_phase(uvm_phase phase);
            gmii_base_seq s;
            phase.raise_objection(this);
            s = make_seq();
            s.start(env.agent.sqr);
            #1us;
            phase.drop_objection(this);
        endtask
    endclass

    class top_smoke_test extends top_base_test;
        `uvm_component_utils(top_smoke_test)

        function new(string name, uvm_component parent);
            super.new(name, parent);
        endfunction
    endclass

    class top_directed_test extends top_base_test;
        `uvm_component_utils(top_directed_test)

        function new(string name, uvm_component parent);
            super.new(name, parent);
        endfunction

        function gmii_base_seq make_seq();
            top_directed_seq s = top_directed_seq::type_id::create("seq");
            return s;
        endfunction
    endclass

    class top_error_test extends top_base_test;
        `uvm_component_utils(top_error_test)

        function new(string name, uvm_component parent);
            super.new(name, parent);
        endfunction

        function gmii_base_seq make_seq();
            top_error_seq s = top_error_seq::type_id::create("seq");
            s.count = 33;
            return s;
        endfunction
    endclass

    class top_mixed_test extends top_base_test;
        `uvm_component_utils(top_mixed_test)

        function new(string name, uvm_component parent);
            super.new(name, parent);
        endfunction

        function gmii_base_seq make_seq();
            top_mixed_seq s = top_mixed_seq::type_id::create("seq");
            s.count = 200;
            return s;
        endfunction
    endclass

endpackage
