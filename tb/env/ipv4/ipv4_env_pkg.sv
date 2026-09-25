package ipv4_env_pkg;
    import uvm_pkg::*;
    `include "uvm_macros.svh"
    import tb_utils_pkg::*;
    import stream_pkg::*;

    // ipv4 parser limits
    localparam int MAX_IPV4_BYTES = 1500;

    // one ipv4 packet described by its header fields
    class ipv4_pkt_item extends uvm_object;
        `uvm_object_utils(ipv4_pkt_item)

        rand bit [3:0] version;
        rand bit [3:0] ihl;
        rand bit [7:0] tos;
        rand bit [15:0] total_len;
        rand bit [15:0] id;
        rand bit rsv;
        rand bit df;
        rand bit mf;
        rand bit [12:0] frag_off;
        rand bit [7:0] ttl;
        rand bit [7:0] protocol;
        rand bit [31:0] src;
        rand bit [31:0] dst;
        rand int unsigned payload_len;
        rand byte unsigned payload[];
        rand int unsigned pad;
        rand bit bad_checksum;

        constraint c_header {
            soft version == 4;
            soft ihl == 5;
            soft rsv == 0;
            soft mf == 0;
            soft frag_off == 0;
            soft bad_checksum == 0;
        }
        constraint c_payload {
            soft payload_len inside {[0:120]};
            payload.size() == payload_len;
            soft total_len == 20 + payload_len;
        }
        constraint c_pad { soft pad inside {[0:6]}; }

        function new(string name = "ipv4_pkt_item");
            super.new(name);
        endfunction

        function bytes_t header();
            bytes_t h;
            bit [7:0] version_ihl = {version, ihl};
            bit [7:0] flags_off = {rsv, df, mf, frag_off[12:8]};
            bit [15:0] c;
            h.push_back(version_ihl);
            h.push_back(tos);
            h.push_back(total_len[15:8]);
            h.push_back(total_len[7:0]);
            h.push_back(id[15:8]);
            h.push_back(id[7:0]);
            h.push_back(flags_off);
            h.push_back(frag_off[7:0]);
            h.push_back(ttl);
            h.push_back(protocol);
            h.push_back(8'h00);
            h.push_back(8'h00);
            for (int i = 3; i >= 0; i--) h.push_back(src[8*i +: 8]);
            for (int i = 3; i >= 0; i--) h.push_back(dst[8*i +: 8]);
            c = ~ones_sum(h);
            if (bad_checksum) c ^= 16'h0100;
            h[10] = c[15:8];
            h[11] = c[7:0];
            return h;
        endfunction

        // header, payload, then trailing padding the parser must ignore
        function bytes_t to_bytes();
            bytes_t b = header();
            foreach (payload[i]) b.push_back(payload[i]);
            repeat (pad) b.push_back(8'h00);
            return b;
        endfunction

        function string convert2string();
            return $sformatf("ver %0d ihl %0d len %0d df %0b mf %0b off %0d proto %0d payload %0d pad %0d bad_csum %0b",
                             version, ihl, total_len, df, mf, frag_off, protocol,
                             payload_len, pad, bad_checksum);
        endfunction
    endclass

    // what the parser put out for one packet
    class ipv4_out_item extends out_item;
        `uvm_object_utils(ipv4_out_item)

        bytes_t bytes;
        bit error;
        bit checksum_error;
        bit checksum_dc;     // expected only, checksum flag not predictable
        int eop_pos = -1;    // payload bytes seen before end_of_payload
        int eop_count;
        bit [7:0] protocol;
        bit [31:0] src;
        bit [31:0] dst;

        function new(string name = "ipv4_out_item");
            super.new(name);
        endfunction

        function bit check(out_item act, output string why);
            ipv4_out_item a;
            if (!$cast(a, act)) begin
                why = "wrong item type";
                return 0;
            end
            if (a.error != error) begin
                why = "ipv4_error";
                return 0;
            end
            if (!checksum_dc && a.checksum_error != checksum_error) begin
                why = "header_checksum_error";
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
            if (a.protocol != protocol || a.src != src || a.dst != dst) begin
                why = "header field windows";
                return 0;
            end
            return 1;
        endfunction

        function string convert2string();
            return $sformatf("err %0b csum_err %0b eop %0d@%0d proto %0d src %08h dst %08h %s",
                             error, checksum_error, eop_count, eop_pos, protocol, src, dst, hex(bytes));
        endfunction
    endclass

    // one item per packet from start_of_packet to end_of_packet
    class ipv4_out_monitor extends uvm_monitor;
        `uvm_component_utils(ipv4_out_monitor)

        virtual ipv4_out_if vif;
        uvm_analysis_port #(out_item) ap;

        function new(string name, uvm_component parent);
            super.new(name, parent);
        endfunction

        function void build_phase(uvm_phase phase);
            super.build_phase(phase);
            ap = new("ap", this);
            if (!uvm_config_db #(virtual ipv4_out_if)::get(this, "", "vif", vif)) begin
                `uvm_fatal("NOVIF", "ipv4_out_if not set")
            end
        endfunction

        task run_phase(uvm_phase phase);
            ipv4_out_item t;
            forever begin
                @(vif.mon_cb);
                if (vif.mon_cb.start_of_packet) t = ipv4_out_item::type_id::create("t");
                if (t != null) begin
                    if (vif.mon_cb.protocol_valid) t.protocol = vif.mon_cb.o_stream;
                    if (vif.mon_cb.source_ip_valid) t.src = {t.src[23:0], vif.mon_cb.o_stream};
                    if (vif.mon_cb.destination_ip_valid) t.dst = {t.dst[23:0], vif.mon_cb.o_stream};
                    if (vif.mon_cb.end_of_payload) begin
                        t.eop_count++;
                        t.eop_pos = t.bytes.size();
                    end
                    if (vif.mon_cb.payload_ipv4_valid) t.bytes.push_back(vif.mon_cb.o_stream);
                    if (vif.mon_cb.ipv4_error) t.error = 1;
                    if (vif.mon_cb.header_checksum_error) t.checksum_error = 1;
                    if (vif.mon_cb.end_of_packet) begin
                        `uvm_info("OUTMON", t.convert2string(), UVM_MEDIUM)
                        ap.write(t);
                        t = null;
                    end
                end
            end
        endtask
    endclass

    class ipv4_ref_model extends uvm_subscriber #(stream_obs_item);
        `uvm_component_utils(ipv4_ref_model)

        uvm_analysis_port #(out_item) ap;

        function new(string name, uvm_component parent);
            super.new(name, parent);
        endfunction

        function void build_phase(uvm_phase phase);
            super.build_phase(phase);
            ap = new("ap", this);
        endfunction

        static function ipv4_out_item predict(bytes_t b, bit err);
            ipv4_out_item e = ipv4_out_item::type_id::create("exp");
            int n = b.size();
            int total;
            bit header_bad;
            bit checksum_bad;

            e.checksum_dc = 1;
            // anything cut inside the header is a truncation
            if (n < 20) begin
                e.error = 1;
                return e;
            end

            total = be16(b, 2);
            header_bad = (b[0] != 8'h45)
                       || (total < 20) || (total > MAX_IPV4_BYTES)
                       // no reassembly so any flag or offset means a fragment
                       || (b[6][7:5] != 0) || (b[6][4:0] != 0) || (b[7] != 0);
            checksum_bad = ones_sum(b[0:19]) != 16'hFFFF;

            e.error = header_bad || checksum_bad || err || (n < total);
            e.checksum_dc = header_bad || err;
            e.checksum_error = checksum_bad;
            if (e.error) begin
                // speculative bytes can only come from a sane length
                if (!header_bad) for (int i = 20; i < n && i < total; i++) e.bytes.push_back(b[i]);
                return e;
            end

            // bytes past total length are ethernet padding
            for (int i = 20; i < total; i++) e.bytes.push_back(b[i]);
            e.eop_count = 1;
            e.eop_pos = (total == 20) ? 0 : total - 21;
            e.protocol = b[9];
            e.src = be32(b, 12);
            e.dst = be32(b, 16);
            return e;
        endfunction

        function void write(stream_obs_item t);
            ap.write(predict(t.bytes, t.err));
        endfunction
    endclass

    class ipv4_coverage extends uvm_subscriber #(stream_obs_item);
        `uvm_component_utils(ipv4_coverage)

        int payload_len;
        bit [7:0] version_ihl;
        bit [2:0] flags;
        bit frag_off_set;
        bit checksum_good;
        bit padded;
        bit err;

        covergroup cg;
            cp_len: coverpoint payload_len {
                bins header_cut = {[-20:-1]};
                bins empty      = {0};
                bins short_len  = {[1:63]};
                bins long_len   = {[64:1480]};
                bins too_long   = {[1481:$]};
            }
            cp_version: coverpoint version_ihl {
                bins good = {8'h45};
                bins bad  = default;
            }
            cp_flags: coverpoint flags {
                bins none = {3'b000};
                bins df   = {3'b010};
                bins mf   = {3'b001};
                bins rsv  = {3'b100};
            }
            cp_offset: coverpoint frag_off_set;
            cp_checksum: coverpoint checksum_good;
            cp_padded: coverpoint padded;
            cp_err: coverpoint err;
        endgroup

        function new(string name, uvm_component parent);
            super.new(name, parent);
            cg = new();
        endfunction

        function void write(stream_obs_item t);
            bytes_t b = t.bytes;
            payload_len = (b.size() < 4) ? b.size() - 20 : int'(be16(b, 2)) - 20;
            version_ihl = b[0];
            flags = (b.size() > 6) ? b[6][7:5] : 3'b000;
            frag_off_set = (b.size() > 7) && ((b[6][4:0] != 0) || (b[7] != 0));
            checksum_good = (b.size() >= 20) && (ones_sum(b[0:19]) == 16'hFFFF);
            padded = (b.size() >= 4) && (b.size() > int'(be16(b, 2)));
            err = t.err;
            cg.sample();
        endfunction

        function void report_phase(uvm_phase phase);
            `uvm_info("COV", $sformatf("ipv4 coverage %0.1f%%", cg.get_coverage()), UVM_LOW)
        endfunction
    endclass

    class ipv4_env extends uvm_env;
        `uvm_component_utils(ipv4_env)

        stream_agent agent;
        ipv4_out_monitor out_mon;
        ipv4_ref_model ref_model;
        out_scoreboard scb;
        ipv4_coverage cov;

        function new(string name, uvm_component parent);
            super.new(name, parent);
        endfunction

        function void build_phase(uvm_phase phase);
            super.build_phase(phase);
            agent     = stream_agent::type_id::create("agent", this);
            out_mon   = ipv4_out_monitor::type_id::create("out_mon", this);
            ref_model = ipv4_ref_model::type_id::create("ref_model", this);
            scb       = out_scoreboard::type_id::create("scb", this);
            cov       = ipv4_coverage::type_id::create("cov", this);
        endfunction

        function void connect_phase(uvm_phase phase);
            agent.mon.ap.connect(ref_model.analysis_export);
            agent.mon.ap.connect(cov.analysis_export);
            ref_model.ap.connect(scb.exp_fifo.analysis_export);
            out_mon.ap.connect(scb.act_fifo.analysis_export);
        endfunction
    endclass

    // good packets with df set half the time and random padding
    class ipv4_good_seq extends stream_base_seq;
        `uvm_object_utils(ipv4_good_seq)

        function new(string name = "ipv4_good_seq");
            super.new(name);
        endfunction

        virtual function void shape(ipv4_pkt_item p, int unsigned i);
            if (!p.randomize()) `uvm_fatal("RAND", "ipv4 randomize failed")
        endfunction

        function void fill(stream_item t, int unsigned i);
            ipv4_pkt_item p = ipv4_pkt_item::type_id::create("p");
            shape(p, i);
            t.bytes = p.to_bytes();
            `uvm_info("SEQ", p.convert2string(), UVM_HIGH)
        endfunction
    endclass

    // every header rule, stream error, and truncation in turn
    class ipv4_error_seq extends ipv4_good_seq;
        `uvm_object_utils(ipv4_error_seq)

        function new(string name = "ipv4_error_seq");
            super.new(name);
        endfunction

        // start from a good packet and break one thing, xsim stalls when
        // inline constraints fight the soft header defaults
        function void shape(ipv4_pkt_item p, int unsigned i);
            super.shape(p, i);
            case (i % 10)
                0: p.version ^= 4'($urandom_range(1, 15));
                1: p.ihl ^= 4'($urandom_range(1, 15));
                2: p.total_len = $urandom_range(0, 19);
                3: p.total_len = $urandom_range(1501, 1600);
                4: p.mf = 1;
                5: p.frag_off = $urandom_range(1, 8191);
                6: p.rsv = 1;
                7: p.bad_checksum = 1;
                // length says more than was sent
                8: begin
                    p.total_len += 5;
                    p.pad = 0;
                end
                // length says less, the rest is padding and fine
                9: begin
                    if (p.payload_len >= 4) p.total_len -= 4;
                    else p.pad += 4;
                end
            endcase
        endfunction
    endclass

    // data_error and early data_end anywhere in a good packet
    class ipv4_stream_error_seq extends ipv4_good_seq;
        `uvm_object_utils(ipv4_stream_error_seq)

        function new(string name = "ipv4_stream_error_seq");
            super.new(name);
        endfunction

        function void fill(stream_item t, int unsigned i);
            super.fill(t, i);
            if (i % 2) t.error_at = $urandom_range(0, t.bytes.size() - 1);
            else       t.truncate_at = $urandom_range(1, t.bytes.size() - 1);
        endfunction
    endclass

    class ipv4_random_seq extends ipv4_good_seq;
        `uvm_object_utils(ipv4_random_seq)

        ipv4_error_seq errors;

        function new(string name = "ipv4_random_seq");
            super.new(name);
            errors = new("errors");
        endfunction

        function void shape(ipv4_pkt_item p, int unsigned i);
            if ($urandom_range(0, 3) == 0) errors.shape(p, $urandom_range(0, 9));
            else super.shape(p, i);
        endfunction

        function void fill(stream_item t, int unsigned i);
            super.fill(t, i);
            case ($urandom_range(0, 19))
                0: t.error_at = $urandom_range(0, t.bytes.size() - 1);
                1: t.truncate_at = $urandom_range(1, t.bytes.size() - 1);
                default: ;
            endcase
        endfunction
    endclass

    class ipv4_base_test extends uvm_test;
        `uvm_component_utils(ipv4_base_test)

        ipv4_env env;

        function new(string name, uvm_component parent);
            super.new(name, parent);
        endfunction

        function void build_phase(uvm_phase phase);
            super.build_phase(phase);
            env = ipv4_env::type_id::create("env", this);
        endfunction

        virtual function stream_base_seq make_seq();
            ipv4_good_seq s = ipv4_good_seq::type_id::create("seq");
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

    class ipv4_smoke_test extends ipv4_base_test;
        `uvm_component_utils(ipv4_smoke_test)

        function new(string name, uvm_component parent);
            super.new(name, parent);
        endfunction
    endclass

    class ipv4_error_test extends ipv4_base_test;
        `uvm_component_utils(ipv4_error_test)

        function new(string name, uvm_component parent);
            super.new(name, parent);
        endfunction

        function stream_base_seq make_seq();
            ipv4_error_seq s = ipv4_error_seq::type_id::create("seq");
            s.count = 30;
            return s;
        endfunction
    endclass

    class ipv4_stream_error_test extends ipv4_base_test;
        `uvm_component_utils(ipv4_stream_error_test)

        function new(string name, uvm_component parent);
            super.new(name, parent);
        endfunction

        function stream_base_seq make_seq();
            ipv4_stream_error_seq s = ipv4_stream_error_seq::type_id::create("seq");
            s.count = 20;
            return s;
        endfunction
    endclass

    class ipv4_stall_test extends ipv4_base_test;
        `uvm_component_utils(ipv4_stall_test)

        function new(string name, uvm_component parent);
            super.new(name, parent);
        endfunction

        function stream_base_seq make_seq();
            ipv4_random_seq s = ipv4_random_seq::type_id::create("seq");
            s.count = 60;
            s.stall_pct = 30;
            return s;
        endfunction
    endclass

    class ipv4_random_test extends ipv4_base_test;
        `uvm_component_utils(ipv4_random_test)

        function new(string name, uvm_component parent);
            super.new(name, parent);
        endfunction

        function stream_base_seq make_seq();
            ipv4_random_seq s = ipv4_random_seq::type_id::create("seq");
            s.count = 200;
            return s;
        endfunction
    endclass

endpackage
