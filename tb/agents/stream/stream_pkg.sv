package stream_pkg;
    import uvm_pkg::*;
    `include "uvm_macros.svh"
    import tb_utils_pkg::*;

    // one packet on the byte stream the upper parsers take
    class stream_item extends uvm_sequence_item;
        `uvm_object_utils(stream_item)

        bytes_t pseudo;      // pseudo header bytes sent before the packet
        bytes_t bytes;       // packet bytes, data_start on the first
        int last_at = -1;    // byte index that carries data_last
        int error_at = -1;   // byte index that carries data_error
        int truncate_at = -1;

        rand int unsigned gap;
        rand int unsigned stall_pct;

        constraint c_gap { gap inside {[2:8]}; }
        constraint c_stall { soft stall_pct == 0; stall_pct <= 50; }

        function new(string name = "stream_item");
            super.new(name);
        endfunction

        function string convert2string();
            return $sformatf("%0d bytes pseudo %0d last_at %0d error_at %0d truncate_at %0d: %s",
                             bytes.size(), pseudo.size(), last_at, error_at, truncate_at, hex(bytes));
        endfunction
    endclass

    // what the input monitor saw between data_start and data_end
    class stream_obs_item extends uvm_sequence_item;
        `uvm_object_utils(stream_obs_item)

        bytes_t pseudo;
        bytes_t bytes;
        int last_at = -1;
        bit err;

        function new(string name = "stream_obs_item");
            super.new(name);
        endfunction

        function string convert2string();
            return $sformatf("%0d bytes last_at %0d err %0b: %s", bytes.size(), last_at, err, hex(bytes));
        endfunction
    endclass

    typedef uvm_sequencer #(stream_item) stream_sequencer;

    class stream_driver extends uvm_driver #(stream_item);
        `uvm_component_utils(stream_driver)

        virtual stream_if vif;

        function new(string name, uvm_component parent);
            super.new(name, parent);
        endfunction

        function void build_phase(uvm_phase phase);
            super.build_phase(phase);
            if (!uvm_config_db #(virtual stream_if)::get(this, "", "vif", vif)) begin
                `uvm_fatal("NOVIF", "stream_if not set")
            end
        endfunction

        task run_phase(uvm_phase phase);
            idle();
            vif.drv_cb.data_end <= 1'b0;
            wait (vif.rst === 1'b0);
            repeat (4) @(vif.drv_cb);
            forever begin
                seq_item_port.get_next_item(req);
                drive(req);
                seq_item_port.item_done();
            end
        endtask

        function void idle();
            vif.drv_cb.data         <= '0;
            vif.drv_cb.data_valid   <= 1'b0;
            vif.drv_cb.data_start   <= 1'b0;
            vif.drv_cb.data_last    <= 1'b0;
            vif.drv_cb.data_error   <= 1'b0;
            vif.drv_cb.pseudo_valid <= 1'b0;
        endfunction

        task drive(stream_item t);
            int n = t.bytes.size();
            if (t.truncate_at >= 0 && t.truncate_at < n) n = t.truncate_at;
            `uvm_info("DRV", t.convert2string(), UVM_HIGH)

            // pseudo header goes in while the parser is idle
            foreach (t.pseudo[i]) begin
                @(vif.drv_cb);
                idle();
                vif.drv_cb.data         <= t.pseudo[i];
                vif.drv_cb.pseudo_valid <= 1'b1;
            end

            for (int i = 0; i < n; i++) begin
                // random stalls between bytes
                while ($urandom_range(99) < t.stall_pct) begin
                    @(vif.drv_cb);
                    idle();
                end
                @(vif.drv_cb);
                idle();
                vif.drv_cb.data       <= t.bytes[i];
                vif.drv_cb.data_valid <= 1'b1;
                vif.drv_cb.data_start <= (i == 0);
                vif.drv_cb.data_last  <= (i == t.last_at);
                vif.drv_cb.data_error <= (i == t.error_at);
            end

            // data_end lands a cycle after the last byte like ethernet end_of_packet
            @(vif.drv_cb);
            idle();
            vif.drv_cb.data_end <= 1'b1;
            @(vif.drv_cb);
            vif.drv_cb.data_end <= 1'b0;
            repeat (t.gap) @(vif.drv_cb);
        endtask
    endclass

    class stream_monitor extends uvm_monitor;
        `uvm_component_utils(stream_monitor)

        virtual stream_if vif;
        uvm_analysis_port #(stream_obs_item) ap;

        function new(string name, uvm_component parent);
            super.new(name, parent);
        endfunction

        function void build_phase(uvm_phase phase);
            super.build_phase(phase);
            ap = new("ap", this);
            if (!uvm_config_db #(virtual stream_if)::get(this, "", "vif", vif)) begin
                `uvm_fatal("NOVIF", "stream_if not set")
            end
        endfunction

        task run_phase(uvm_phase phase);
            stream_obs_item t = stream_obs_item::type_id::create("t");
            forever begin
                @(vif.mon_cb);
                if (vif.mon_cb.rst) begin
                    t = stream_obs_item::type_id::create("t");
                end else begin
                    if (vif.mon_cb.pseudo_valid) t.pseudo.push_back(vif.mon_cb.data);
                    if (vif.mon_cb.data_valid) begin
                        if (vif.mon_cb.data_last) t.last_at = t.bytes.size();
                        t.bytes.push_back(vif.mon_cb.data);
                    end
                    if (vif.mon_cb.data_error) t.err = 1;
                    if (vif.mon_cb.data_end) begin
                        if (t.bytes.size() > 0) begin
                            `uvm_info("MON", t.convert2string(), UVM_MEDIUM)
                            ap.write(t);
                        end
                        t = stream_obs_item::type_id::create("t");
                    end
                end
            end
        endtask
    endclass

    class stream_agent extends uvm_agent;
        `uvm_component_utils(stream_agent)

        stream_sequencer sqr;
        stream_driver drv;
        stream_monitor mon;

        function new(string name, uvm_component parent);
            super.new(name, parent);
        endfunction

        function void build_phase(uvm_phase phase);
            super.build_phase(phase);
            mon = stream_monitor::type_id::create("mon", this);
            if (get_is_active() == UVM_ACTIVE) begin
                sqr = stream_sequencer::type_id::create("sqr", this);
                drv = stream_driver::type_id::create("drv", this);
            end
        endfunction

        function void connect_phase(uvm_phase phase);
            if (get_is_active() == UVM_ACTIVE) begin
                drv.seq_item_port.connect(sqr.seq_item_export);
            end
        endfunction
    endclass

    // count packets, subclasses build each one
    class stream_base_seq extends uvm_sequence #(stream_item);
        `uvm_object_utils(stream_base_seq)

        int unsigned count = 10;
        int unsigned stall_pct = 0;

        function new(string name = "stream_base_seq");
            super.new(name);
        endfunction

        virtual function void fill(stream_item t, int unsigned i);
            t.bytes = '{8'h00};
        endfunction

        task body();
            stream_item t;
            for (int unsigned i = 0; i < count; i++) begin
                t = stream_item::type_id::create($sformatf("pkt%0d", i));
                start_item(t);
                if (!t.randomize() with { stall_pct == local::stall_pct; })
                    `uvm_fatal("RAND", "stream item randomize failed")
                fill(t, i);
                finish_item(t);
            end
        endtask
    endclass

endpackage
