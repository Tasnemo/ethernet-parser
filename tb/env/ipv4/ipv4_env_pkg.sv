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

    class ipv4_env extends uvm_env;
        `uvm_component_utils(ipv4_env)

        stream_agent agent;

        function new(string name, uvm_component parent);
            super.new(name, parent);
        endfunction

        function void build_phase(uvm_phase phase);
            super.build_phase(phase);
            agent = stream_agent::type_id::create("agent", this);
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

endpackage
