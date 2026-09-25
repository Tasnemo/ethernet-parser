module tb_ipv4;
    import uvm_pkg::*;
    import ipv4_env_pkg::*;

    logic clk = 1'b0;
    always #4ns clk = ~clk;

    stream_if in (clk);
    ipv4_out_if out (clk);

    ipv4_parser #(
        .MAX_IPV4_BYTES(MAX_IPV4_BYTES)
    ) dut (
        .clk(clk),
        .rst(in.rst),
        .data(in.data),
        .data_valid(in.data_valid),
        .data_start(in.data_start),
        .data_end(in.data_end),
        .data_error(in.data_error),
        .o_stream(out.o_stream),
        .header_ipv4_valid(out.header_ipv4_valid),
        .total_length_valid(out.total_length_valid),
        .protocol_valid(out.protocol_valid),
        .source_ip_valid(out.source_ip_valid),
        .destination_ip_valid(out.destination_ip_valid),
        .payload_ipv4_valid(out.payload_ipv4_valid),
        .start_of_packet(out.start_of_packet),
        .end_of_payload(out.end_of_payload),
        .end_of_packet(out.end_of_packet),
        .header_checksum_error(out.header_checksum_error),
        .ipv4_error(out.ipv4_error)
    );

    initial begin
        in.rst = 1'b1;
        repeat (5) @(posedge clk);
        in.rst <= 1'b0;
    end

    initial begin
        uvm_config_db #(virtual stream_if)::set(null, "uvm_test_top.env.agent*", "vif", in);
        uvm_config_db #(virtual ipv4_out_if)::set(null, "uvm_test_top.env.out_mon", "vif", out);
        run_test();
    end
endmodule
