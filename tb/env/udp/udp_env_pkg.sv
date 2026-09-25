package udp_env_pkg;
    import uvm_pkg::*;
    `include "uvm_macros.svh"
    import tb_utils_pkg::*;
    import stream_pkg::*;

    // udp parser limits
    localparam int MAX_UDP_BYTES = 1480;

    // one udp segment plus the ip addresses for its pseudo header
    class udp_seg_item extends uvm_object;
        `uvm_object_utils(udp_seg_item)

        rand bit [31:0] src_ip;
        rand bit [31:0] dst_ip;
        rand bit [15:0] src_port;
        rand bit [15:0] dst_port;
        rand int unsigned payload_len;
        rand byte unsigned payload[];

        // error knobs set after randomize
        int length_delta;
        bit zero_checksum;
        bit bad_checksum;

        constraint c_port { dst_port != 0; }
        constraint c_payload {
            soft payload_len inside {[0:120]};
            payload.size() == payload_len;
        }

        function new(string name = "udp_seg_item");
            super.new(name);
        endfunction

        function bytes_t pseudo();
            bytes_t p;
            for (int i = 3; i >= 0; i--) p.push_back(src_ip[8*i +: 8]);
            for (int i = 3; i >= 0; i--) p.push_back(dst_ip[8*i +: 8]);
            return p;
        endfunction

        function bytes_t to_bytes();
            bytes_t b;
            bit [15:0] length = 16'(8 + payload_len + length_delta);
            bit [15:0] c;
            b.push_back(src_port[15:8]);
            b.push_back(src_port[7:0]);
            b.push_back(dst_port[15:8]);
            b.push_back(dst_port[7:0]);
            b.push_back(length[15:8]);
            b.push_back(length[7:0]);
            b.push_back(8'h00);
            b.push_back(8'h00);
            foreach (payload[i]) b.push_back(payload[i]);

            // an all zero result goes out as ffff since zero means skipped
            c = ~udp_sum(pseudo(), b);
            if (c == 16'h0000) c = 16'hFFFF;
            if (bad_checksum) c ^= (c == 16'h0001) ? 16'h0002 : 16'h0001;
            if (zero_checksum) c = 16'h0000;
            b[6] = c[15:8];
            b[7] = c[7:0];
            return b;
        endfunction

        function string convert2string();
            return $sformatf("ports %0d->%0d payload %0d length_delta %0d zero_csum %0b bad_csum %0b",
                             src_port, dst_port, payload_len, length_delta, zero_checksum, bad_checksum);
        endfunction
    endclass

    // what the parser put out for one segment
    class udp_out_item extends out_item;
        `uvm_object_utils(udp_out_item)

        bytes_t bytes;
        bit error;
        bit checksum_error;
        bit checksum_dc;
        int eop_pos = -1;
        int eop_count;
        bit [15:0] src_port;
        bit [15:0] dst_port;
        bit [15:0] length;

        function new(string name = "udp_out_item");
            super.new(name);
        endfunction

        function bit check(out_item act, output string why);
            udp_out_item a;
            if (!$cast(a, act)) begin
                why = "wrong item type";
                return 0;
            end
            if (a.error != error) begin
                why = "udp_error";
                return 0;
            end
            if (!checksum_dc && a.checksum_error != checksum_error) begin
                why = "udp_checksum_error";
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
                why = "payload bytes";
                return 0;
            end
            if (a.eop_count != 1 || a.eop_pos != eop_pos) begin
                why = "end_of_payload";
                return 0;
            end
            if (a.src_port != src_port || a.dst_port != dst_port || a.length != length) begin
                why = "header field windows";
                return 0;
            end
            return 1;
        endfunction

        function string convert2string();
            return $sformatf("err %0b csum_err %0b eop %0d@%0d ports %0d->%0d len %0d %s",
                             error, checksum_error, eop_count, eop_pos, src_port, dst_port,
                             length, hex(bytes));
        endfunction
    endclass

    class udp_out_monitor extends uvm_monitor;
        `uvm_component_utils(udp_out_monitor)

        virtual udp_out_if vif;
        uvm_analysis_port #(out_item) ap;

        function new(string name, uvm_component parent);
            super.new(name, parent);
        endfunction

        function void build_phase(uvm_phase phase);
            super.build_phase(phase);
            ap = new("ap", this);
            if (!uvm_config_db #(virtual udp_out_if)::get(this, "", "vif", vif)) begin
                `uvm_fatal("NOVIF", "udp_out_if not set")
            end
        endfunction

        task run_phase(uvm_phase phase);
            udp_out_item t;
            forever begin
                @(vif.mon_cb);
                if (vif.mon_cb.start_of_packet) t = udp_out_item::type_id::create("t");
                if (t != null) begin
                    if (vif.mon_cb.source_port_valid) t.src_port = {t.src_port[7:0], vif.mon_cb.o_stream};
                    if (vif.mon_cb.destination_port_valid) t.dst_port = {t.dst_port[7:0], vif.mon_cb.o_stream};
                    if (vif.mon_cb.length_valid) t.length = {t.length[7:0], vif.mon_cb.o_stream};
                    if (vif.mon_cb.end_of_payload) begin
                        t.eop_count++;
                        t.eop_pos = t.bytes.size();
                    end
                    if (vif.mon_cb.payload_udp_valid) t.bytes.push_back(vif.mon_cb.o_stream);
                    if (vif.mon_cb.udp_error) t.error = 1;
                    if (vif.mon_cb.udp_checksum_error) t.checksum_error = 1;
                    if (vif.mon_cb.end_of_packet) begin
                        `uvm_info("OUTMON", t.convert2string(), UVM_MEDIUM)
                        ap.write(t);
                        t = null;
                    end
                end
            end
        endtask
    endclass

    class udp_ref_model extends uvm_subscriber #(stream_obs_item);
        `uvm_component_utils(udp_ref_model)

        uvm_analysis_port #(out_item) ap;

        function new(string name, uvm_component parent);
            super.new(name, parent);
        endfunction

        function void build_phase(uvm_phase phase);
            super.build_phase(phase);
            ap = new("ap", this);
        endfunction

        static function udp_out_item predict(bytes_t pseudo, bytes_t b, int last_at, bit err);
            udp_out_item e = udp_out_item::type_id::create("exp");
            int n = b.size();
            int length;
            bit header_bad;
            bit misaligned;
            bit truncated;
            bit checksum_bad;

            e.checksum_dc = 1;
            if (n < 8) begin
                e.error = 1;
                return e;
            end

            length = be16(b, 4);
            header_bad = (length < 8) || (length > MAX_UDP_BYTES) || (be16(b, 2) == 0);
            // data_last from ipv4 has to land on the last udp byte
            misaligned = (last_at != length - 1);
            truncated = (n < length);
            checksum_bad = !header_bad && !truncated && (be16(b, 6) != 0)
                         && (udp_sum(pseudo, b[0:length-1]) != 16'hFFFF);

            e.error = header_bad || misaligned || truncated || err || checksum_bad;
            e.checksum_dc = header_bad || misaligned || truncated || err;
            e.checksum_error = checksum_bad;
            if (e.error) begin
                if (!header_bad) for (int i = 8; i < n && i < length; i++) e.bytes.push_back(b[i]);
                return e;
            end

            for (int i = 8; i < length; i++) e.bytes.push_back(b[i]);
            e.eop_count = 1;
            e.eop_pos = (length == 8) ? 0 : length - 9;
            e.src_port = be16(b, 0);
            e.dst_port = be16(b, 2);
            e.length = length;
            return e;
        endfunction

        function void write(stream_obs_item t);
            ap.write(predict(t.pseudo, t.bytes, t.last_at, t.err));
        endfunction
    endclass

    class udp_coverage extends uvm_subscriber #(stream_obs_item);
        `uvm_component_utils(udp_coverage)

        int payload_len;
        bit odd;
        bit port_zero;
        bit checksum_zero;
        bit aligned;
        bit err;

        covergroup cg;
            cp_len: coverpoint payload_len {
                bins header_cut = {[-8:-1]};
                bins empty      = {0};
                bins short_len  = {[1:63]};
                bins long_len   = {[64:1472]};
                bins too_long   = {[1473:$]};
            }
            cp_odd: coverpoint odd;
            cp_port_zero: coverpoint port_zero;
            cp_checksum_zero: coverpoint checksum_zero;
            cp_aligned: coverpoint aligned;
            cp_err: coverpoint err;
            x_len_odd: cross cp_len, cp_odd {
                ignore_bins cut = binsof(cp_len.header_cut) || binsof(cp_len.empty)
                                  || binsof(cp_len.too_long);
            }
        endgroup

        function new(string name, uvm_component parent);
            super.new(name, parent);
            cg = new();
        endfunction

        function void write(stream_obs_item t);
            bytes_t b = t.bytes;
            payload_len = (b.size() < 6) ? b.size() - 8 : int'(be16(b, 4)) - 8;
            odd = payload_len[0];
            port_zero = (b.size() >= 4) && (be16(b, 2) == 0);
            checksum_zero = (b.size() >= 8) && (be16(b, 6) == 0);
            aligned = (b.size() >= 6) && (t.last_at == int'(be16(b, 4)) - 1);
            err = t.err;
            cg.sample();
        endfunction

        function void report_phase(uvm_phase phase);
            `uvm_info("COV", $sformatf("udp coverage %0.1f%%", cg.get_coverage()), UVM_LOW)
        endfunction
    endclass

    class udp_env extends uvm_env;
        `uvm_component_utils(udp_env)

        stream_agent agent;
        udp_out_monitor out_mon;
        udp_ref_model ref_model;
        out_scoreboard scb;
        udp_coverage cov;

        function new(string name, uvm_component parent);
            super.new(name, parent);
        endfunction

        function void build_phase(uvm_phase phase);
            super.build_phase(phase);
            agent     = stream_agent::type_id::create("agent", this);
            out_mon   = udp_out_monitor::type_id::create("out_mon", this);
            ref_model = udp_ref_model::type_id::create("ref_model", this);
            scb       = out_scoreboard::type_id::create("scb", this);
            cov       = udp_coverage::type_id::create("cov", this);
        endfunction

        function void connect_phase(uvm_phase phase);
            agent.mon.ap.connect(ref_model.analysis_export);
            agent.mon.ap.connect(cov.analysis_export);
            ref_model.ap.connect(scb.exp_fifo.analysis_export);
            out_mon.ap.connect(scb.act_fifo.analysis_export);
        endfunction
    endclass

    // good segments, data_last on the final byte like ipv4 end_of_payload
    class udp_good_seq extends stream_base_seq;
        `uvm_object_utils(udp_good_seq)

        function new(string name = "udp_good_seq");
            super.new(name);
        endfunction

        virtual function void shape(udp_seg_item s, int unsigned i);
            if (!s.randomize()) `uvm_fatal("RAND", "udp randomize failed")
        endfunction

        function void fill(stream_item t, int unsigned i);
            udp_seg_item s = udp_seg_item::type_id::create("s");
            shape(s, i);
            t.pseudo = s.pseudo();
            t.bytes = s.to_bytes();
            t.last_at = t.bytes.size() - 1;
            `uvm_info("SEQ", s.convert2string(), UVM_HIGH)
        endfunction
    endclass

    // every udp rule in turn, starting from a good segment
    class udp_error_seq extends udp_good_seq;
        `uvm_object_utils(udp_error_seq)

        function new(string name = "udp_error_seq");
            super.new(name);
        endfunction

        function void shape(udp_seg_item s, int unsigned i);
            super.shape(s, i);
            case (i % 6)
                0: s.length_delta = $urandom_range(0, 7) - int'(8 + s.payload_len);
                1: s.length_delta = $urandom_range(1481, 1600) - int'(8 + s.payload_len);
                2: s.dst_port = 0;
                3: s.bad_checksum = 1;
                4: s.zero_checksum = 1;
                5: s.length_delta = 3;
            endcase
        endfunction

        function void fill(stream_item t, int unsigned i);
            super.fill(t, i);
            case (i % 9)
                // data_last early, late, or missing
                6: t.last_at = $urandom_range(0, t.bytes.size() - 1) - 1;
                7: begin
                    repeat ($urandom_range(1, 4)) t.bytes.push_back(8'($urandom));
                    t.last_at = t.bytes.size() - 1;
                end
                8: t.last_at = -1;
                default: ;
            endcase
        endfunction
    endclass

    class udp_stream_error_seq extends udp_good_seq;
        `uvm_object_utils(udp_stream_error_seq)

        function new(string name = "udp_stream_error_seq");
            super.new(name);
        endfunction

        function void fill(stream_item t, int unsigned i);
            super.fill(t, i);
            if (i % 2) t.error_at = $urandom_range(0, t.bytes.size() - 1);
            else       t.truncate_at = $urandom_range(1, t.bytes.size() - 1);
        endfunction
    endclass

    class udp_random_seq extends udp_good_seq;
        `uvm_object_utils(udp_random_seq)

        udp_error_seq errors;

        function new(string name = "udp_random_seq");
            super.new(name);
            errors = new("errors");
        endfunction

        function void fill(stream_item t, int unsigned i);
            if ($urandom_range(0, 3) == 0) errors.fill(t, $urandom_range(0, 17));
            else super.fill(t, i);
            case ($urandom_range(0, 19))
                0: t.error_at = $urandom_range(0, t.bytes.size() - 1);
                1: t.truncate_at = $urandom_range(1, t.bytes.size() - 1);
                default: ;
            endcase
        endfunction
    endclass

    class udp_base_test extends uvm_test;
        `uvm_component_utils(udp_base_test)

        udp_env env;

        function new(string name, uvm_component parent);
            super.new(name, parent);
        endfunction

        function void build_phase(uvm_phase phase);
            super.build_phase(phase);
            env = udp_env::type_id::create("env", this);
        endfunction

        virtual function stream_base_seq make_seq();
            udp_good_seq s = udp_good_seq::type_id::create("seq");
            return s;
        endfunction

        task run_phase(uvm_phase phase);
            stream_base_seq s;
            phase.raise_objection(this);
            s = make_seq();
            s.start(env.agent.sqr);
            #1us;
            phase.drop_objection(this);
        endtask
    endclass

    class udp_smoke_test extends udp_base_test;
        `uvm_component_utils(udp_smoke_test)

        function new(string name, uvm_component parent);
            super.new(name, parent);
        endfunction
    endclass

    class udp_error_test extends udp_base_test;
        `uvm_component_utils(udp_error_test)

        function new(string name, uvm_component parent);
            super.new(name, parent);
        endfunction

        function stream_base_seq make_seq();
            udp_error_seq s = udp_error_seq::type_id::create("seq");
            s.count = 36;
            return s;
        endfunction
    endclass

    class udp_stream_error_test extends udp_base_test;
        `uvm_component_utils(udp_stream_error_test)

        function new(string name, uvm_component parent);
            super.new(name, parent);
        endfunction

        function stream_base_seq make_seq();
            udp_stream_error_seq s = udp_stream_error_seq::type_id::create("seq");
            s.count = 20;
            return s;
        endfunction
    endclass

    class udp_stall_test extends udp_base_test;
        `uvm_component_utils(udp_stall_test)

        function new(string name, uvm_component parent);
            super.new(name, parent);
        endfunction

        function stream_base_seq make_seq();
            udp_random_seq s = udp_random_seq::type_id::create("seq");
            s.count = 60;
            s.stall_pct = 30;
            return s;
        endfunction
    endclass

    class udp_random_test extends udp_base_test;
        `uvm_component_utils(udp_random_test)

        function new(string name, uvm_component parent);
            super.new(name, parent);
        endfunction

        function stream_base_seq make_seq();
            udp_random_seq s = udp_random_seq::type_id::create("seq");
            s.count = 200;
            return s;
        endfunction
    endclass

endpackage
