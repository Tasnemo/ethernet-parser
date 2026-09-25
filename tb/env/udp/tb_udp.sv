module tb_udp;
    import uvm_pkg::*;
    import udp_env_pkg::*;

    logic clk = 1'b0;
    always #4ns clk = ~clk;

    stream_if in (clk);
    udp_out_if out (clk);

    udp_parser #(
        .MAX_UDP_BYTES(MAX_UDP_BYTES)
    ) dut (
        .clk(clk),
        .rst(in.rst),
        .data(in.data),
        .data_valid(in.data_valid),
        .data_start(in.data_start),
        .data_last(in.data_last),
        .data_end(in.data_end),
        .data_error(in.data_error),
        .pseudo_valid(in.pseudo_valid),
        .o_stream(out.o_stream),
        .header_udp_valid(out.header_udp_valid),
        .source_port_valid(out.source_port_valid),
        .destination_port_valid(out.destination_port_valid),
        .length_valid(out.length_valid),
        .checksum_valid(out.checksum_valid),
        .payload_udp_valid(out.payload_udp_valid),
        .start_of_packet(out.start_of_packet),
        .end_of_payload(out.end_of_payload),
        .end_of_packet(out.end_of_packet),
        .udp_checksum_error(out.udp_checksum_error),
        .udp_error(out.udp_error)
    );

    initial begin
        in.rst = 1'b1;
        repeat (5) @(posedge clk);
        in.rst <= 1'b0;
    end

    initial begin
        uvm_config_db #(virtual stream_if)::set(null, "uvm_test_top.env.agent*", "vif", in);
        uvm_config_db #(virtual udp_out_if)::set(null, "uvm_test_top.env.out_mon", "vif", out);
        run_test();
    end
endmodule
