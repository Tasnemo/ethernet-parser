package gmii_pkg;
    import uvm_pkg::*;
    `include "uvm_macros.svh"
    import tb_utils_pkg::*;

    // one ethernet frame as it goes on the wire, no preamble
    class eth_frame_item extends uvm_sequence_item;
        `uvm_object_utils(eth_frame_item)

        rand bit [47:0] dst;
        rand bit [47:0] src;
        rand bit [15:0] ethertype;
        rand int unsigned payload_len;
        rand byte unsigned payload[];

        // error knobs, -1 means off
        rand bit corrupt_fcs;
        rand int rx_er_at;
        rand int truncate_at;

        // idle cycles after the frame
        rand int unsigned gap;

        // xsim wants the size set from a plain variable
        constraint c_payload {
            soft payload_len inside {[46:1500]};
            payload.size() == payload_len;
        }
        constraint c_errors {
            soft corrupt_fcs == 0;
            soft rx_er_at == -1;
            soft truncate_at == -1;
        }
        constraint c_gap { gap inside {[12:20]}; }

        function new(string name = "eth_frame_item");
            super.new(name);
        endfunction

        // header, payload, and fcs in wire order
        function bytes_t frame_bytes();
            bytes_t b;
            for (int i = 5; i >= 0; i--) b.push_back(dst[8*i +: 8]);
            for (int i = 5; i >= 0; i--) b.push_back(src[8*i +: 8]);
            b.push_back(ethertype[15:8]);
            b.push_back(ethertype[7:0]);
            foreach (payload[i]) b.push_back(payload[i]);
            append_fcs(b);
            if (corrupt_fcs) b[b.size()-1] ^= 8'h5A;
            return b;
        endfunction

        function string convert2string();
            return $sformatf("type %04h payload %0d fcs_bad %0b rx_er_at %0d truncate_at %0d",
                             ethertype, payload.size(), corrupt_fcs, rx_er_at, truncate_at);
        endfunction
    endclass

    // what the input monitor saw on the pins
    class gmii_obs_item extends uvm_sequence_item;
        `uvm_object_utils(gmii_obs_item)

        bytes_t bytes;
        bit rx_er;

        function new(string name = "gmii_obs_item");
            super.new(name);
        endfunction

        function string convert2string();
            return $sformatf("%0d bytes rx_er %0b: %s", bytes.size(), rx_er, hex(bytes));
        endfunction
    endclass

    typedef uvm_sequencer #(eth_frame_item) gmii_sequencer;

    class gmii_driver extends uvm_driver #(eth_frame_item);
        `uvm_component_utils(gmii_driver)

        virtual gmii_if vif;

        function new(string name, uvm_component parent);
            super.new(name, parent);
        endfunction

        function void build_phase(uvm_phase phase);
            super.build_phase(phase);
            if (!uvm_config_db #(virtual gmii_if)::get(this, "", "vif", vif)) begin
                `uvm_fatal("NOVIF", "gmii_if not set")
            end
        endfunction

        task run_phase(uvm_phase phase);
            vif.drv_cb.rxd   <= '0;
            vif.drv_cb.rx_dv <= 1'b0;
            vif.drv_cb.rx_er <= 1'b0;
            wait (vif.rst === 1'b0);
            repeat (4) @(vif.drv_cb);
            forever begin
                seq_item_port.get_next_item(req);
                drive(req);
                seq_item_port.item_done();
            end
        endtask

        task drive(eth_frame_item t);
            bytes_t b = t.frame_bytes();
            int n = b.size();
            if (t.truncate_at >= 0 && t.truncate_at < n) n = t.truncate_at;
            `uvm_info("DRV", t.convert2string(), UVM_HIGH)
            for (int i = 0; i < n; i++) begin
                @(vif.drv_cb);
                vif.drv_cb.rxd   <= b[i];
                vif.drv_cb.rx_dv <= 1'b1;
                vif.drv_cb.rx_er <= (i == t.rx_er_at);
            end
            // rx_dv low marks the end of the frame
            @(vif.drv_cb);
            vif.drv_cb.rxd   <= '0;
            vif.drv_cb.rx_dv <= 1'b0;
            vif.drv_cb.rx_er <= 1'b0;
            repeat (t.gap) @(vif.drv_cb);
        endtask
    endclass

    // rebuilds each frame from rx_dv high to rx_dv low
    class gmii_monitor extends uvm_monitor;
        `uvm_component_utils(gmii_monitor)

        virtual gmii_if vif;
        uvm_analysis_port #(gmii_obs_item) ap;

        function new(string name, uvm_component parent);
            super.new(name, parent);
        endfunction

        function void build_phase(uvm_phase phase);
            super.build_phase(phase);
            ap = new("ap", this);
            if (!uvm_config_db #(virtual gmii_if)::get(this, "", "vif", vif)) begin
                `uvm_fatal("NOVIF", "gmii_if not set")
            end
        endfunction

        task run_phase(uvm_phase phase);
            gmii_obs_item t;
            forever begin
                @(vif.mon_cb);
                if (vif.mon_cb.rst) begin
                    t = null;
                end else if (vif.mon_cb.rx_dv) begin
                    if (t == null) t = gmii_obs_item::type_id::create("t");
                    t.bytes.push_back(vif.mon_cb.rxd);
                    if (vif.mon_cb.rx_er) t.rx_er = 1;
                end else if (t != null) begin
                    `uvm_info("MON", t.convert2string(), UVM_MEDIUM)
                    ap.write(t);
                    t = null;
                end
            end
        endtask
    endclass

    class gmii_agent extends uvm_agent;
        `uvm_component_utils(gmii_agent)

        gmii_sequencer sqr;
        gmii_driver drv;
        gmii_monitor mon;

        function new(string name, uvm_component parent);
            super.new(name, parent);
        endfunction

        function void build_phase(uvm_phase phase);
            super.build_phase(phase);
            mon = gmii_monitor::type_id::create("mon", this);
            if (get_is_active() == UVM_ACTIVE) begin
                sqr = gmii_sequencer::type_id::create("sqr", this);
                drv = gmii_driver::type_id::create("drv", this);
            end
        endfunction

        function void connect_phase(uvm_phase phase);
            if (get_is_active() == UVM_ACTIVE) begin
                drv.seq_item_port.connect(sqr.seq_item_export);
            end
        endfunction
    endclass

    // count random frames, subclasses shape each one
    class gmii_base_seq extends uvm_sequence #(eth_frame_item);
        `uvm_object_utils(gmii_base_seq)

        int unsigned count = 10;

        function new(string name = "gmii_base_seq");
            super.new(name);
        endfunction

        virtual function void shape(eth_frame_item t, int unsigned i);
            if (!t.randomize()) `uvm_fatal("RAND", "frame randomize failed")
        endfunction

        task body();
            eth_frame_item t;
            for (int unsigned i = 0; i < count; i++) begin
                t = eth_frame_item::type_id::create($sformatf("frame%0d", i));
                start_item(t);
                shape(t, i);
                finish_item(t);
            end
        endtask
    endclass

endpackage
