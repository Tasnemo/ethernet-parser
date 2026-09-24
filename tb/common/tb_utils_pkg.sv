package tb_utils_pkg;
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

    // fcs goes out after the payload
    function automatic void append_fcs(ref bytes_t frame);
        bit [31:0] fcs = crc32(frame);
        for (int i = 3; i >= 0; i--) begin
            frame.push_back(fcs[8*i +: 8]);
        end
    endfunction

    function automatic bit fcs_ok(bytes_t frame);
        bytes_t body;
        bit [31:0] rx;
        int n = frame.size();
        if (n < 4) return 0;
        body = frame[0:n-5];
        rx = {frame[n-4], frame[n-3], frame[n-2], frame[n-1]};
        return crc32(body) == rx;
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

endpackage
