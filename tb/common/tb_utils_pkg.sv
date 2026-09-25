package tb_utils_pkg;
    import uvm_pkg::*;
    `include "uvm_macros.svh"

    typedef byte unsigned bytes_t[$];

    // reflected crc32 as ethernet sends it
    function automatic bit [31:0] crc32(bytes_t data);
        bit [31:0] c = 32'hFFFFFFFF;
        foreach (data[i]) begin
            c = c ^ {24'b0, data[i]};
            for (int b = 0; b < 8; b++) begin
                c = c[0] ? ((c >> 1) ^ 32'hEDB88320) : (c >> 1);
            end
        end
        return ~c;
    endfunction

    // fcs goes out lsb first
    function automatic void append_fcs(ref bytes_t frame);
        bit [31:0] fcs = crc32(frame);
        for (int i = 0; i < 4; i++) begin
            frame.push_back(fcs[8*i +: 8]);
        end
    endfunction

    function automatic bit fcs_ok(bytes_t frame);
        bytes_t body;
        bit [31:0] rx;
        int n = frame.size();
        if (n < 4) return 0;
        body = frame[0:n-5];
        rx = {frame[n-1], frame[n-2], frame[n-3], frame[n-4]};
        return crc32(body) == rx;
    endfunction

    // big endian fields, widths kept exact for xsim
    function automatic bit [15:0] be16(bytes_t data, int i);
        bit [7:0] hi = data[i];
        bit [7:0] lo = data[i+1];
        bit [15:0] v = {hi, lo};
        return v;
    endfunction

    function automatic bit [31:0] be32(bytes_t data, int i);
        bit [15:0] hi = be16(data, i);
        bit [15:0] lo = be16(data, i + 2);
        bit [31:0] v = {hi, lo};
        return v;
    endfunction

    // ones complement sum of big endian words, odd byte pads low
    function automatic bit [15:0] ones_sum(bytes_t data);
        bit [31:0] s = 0;
        bit [7:0] hi;
        bit [7:0] lo;
        bit [15:0] w;
        for (int i = 0; i < data.size(); i += 2) begin
            hi = data[i];
            lo = (i + 1 < data.size()) ? data[i+1] : 8'h00;
            w = {hi, lo};
            s += w;
        end
        while (s[31:16] != 0) begin
            s = s[15:0] + s[31:16];
        end
        return s[15:0];
    endfunction

    // udp sum covers the pseudo header, protocol, length, and segment
    function automatic bit [15:0] udp_sum(bytes_t pseudo, bytes_t seg);
        bytes_t buffer = pseudo;
        buffer.push_back(8'h00);
        buffer.push_back(8'h11);
        buffer.push_back(8'(seg.size() >> 8));
        buffer.push_back(8'(seg.size()));
        foreach (seg[i]) buffer.push_back(seg[i]);
        if (buffer.size() % 2) begin
            buffer.insert(buffer.size() - 1, 8'h00);
        end
        return ones_sum(buffer);
    endfunction

    function automatic string hex(bytes_t data, int limit = 16);
        string s = "";
        foreach (data[i]) begin
            if (i == limit) begin
                s = {s, $sformatf("... (%0d bytes)", data.size())};
                break;
            end
            s = {s, $sformatf("%02h ", data[i])};
        end
        return s;
    endfunction

    // every checked output item says how it differs from the expectation
    virtual class out_item extends uvm_sequence_item;
        function new(string name = "out_item");
            super.new(name);
        endfunction

        pure virtual function bit check(out_item act, output string why);
    endclass

    // speculative bytes before an error only have to be a prefix
    function automatic bit prefix_of(bytes_t part, bytes_t full);
        if (part.size() > full.size()) return 0;
        foreach (part[i]) begin
            if (part[i] != full[i]) return 0;
        end
        return 1;
    endfunction

    // in order compare of predicted and observed items
    class out_scoreboard extends uvm_component;
        `uvm_component_utils(out_scoreboard)

        uvm_tlm_analysis_fifo #(out_item) exp_fifo;
        uvm_tlm_analysis_fifo #(out_item) act_fifo;
        int compared;
        int failed;

        function new(string name, uvm_component parent);
            super.new(name, parent);
        endfunction

        function void build_phase(uvm_phase phase);
            super.build_phase(phase);
            exp_fifo = new("exp_fifo", this);
            act_fifo = new("act_fifo", this);
        endfunction

        task run_phase(uvm_phase phase);
            out_item exp;
            out_item act;
            string why;
            forever begin
                exp_fifo.get(exp);
                act_fifo.get(act);
                compared++;
                if (exp.check(act, why)) begin
                    `uvm_info("SCB", $sformatf("match %0d: %s", compared,
                              act.convert2string()), UVM_HIGH)
                end else begin
                    failed++;
                    `uvm_error("SCB", $sformatf("mismatch %0d: %s\n  exp %s\n  act %s",
                               compared, why, exp.convert2string(),
                               act.convert2string()))
                end
            end
        endtask

        function void check_phase(uvm_phase phase);
            if (compared == 0) begin
                `uvm_error("SCB", "nothing was compared")
            end
            if (!exp_fifo.is_empty() || !act_fifo.is_empty()) begin
                `uvm_error("SCB", $sformatf("unmatched items, %0d expected and %0d observed left",
                           exp_fifo.used(), act_fifo.used()))
            end
        endfunction

        function void report_phase(uvm_phase phase);
            `uvm_info("SCB", $sformatf("%0d compared, %0d failed", compared, failed), UVM_LOW)
        endfunction
    endclass

endpackage
