module tb_ethernet;
    import uvm_pkg::*;
    import eth_env_pkg::*;

    // gmii runs at 125 MHz
    logic clk = 1'b0;
    always #4ns clk = ~clk;

    gmii_if gmii (clk);
    eth_out_if out (clk);

    ethernet_parser dut (
        .rx_clk(clk),
        .rst(gmii.rst),
        .rxd(gmii.rxd),
        .rx_dv(gmii.rx_dv),
        .rx_er(gmii.rx_er),
        .o_stream(out.o_stream),
        .dest_mac_valid(out.dest_mac_valid),
        .sour_mac_valid(out.sour_mac_valid),
        .payload_ether_valid(out.payload_ether_valid),
        .ethertype_valid(out.ethertype_valid),
        .end_of_packet(out.end_of_packet),
        .start_of_packet(out.start_of_packet),
        .fcs_error(out.fcs_error),
        .ether_error(out.ether_error)
    );

    initial begin
        gmii.rst = 1'b1;
        repeat (5) @(posedge clk);
        gmii.rst <= 1'b0;
    end

    initial begin
        uvm_config_db #(virtual gmii_if)::set(null, "uvm_test_top.env.agent*", "vif", gmii);
        uvm_config_db #(virtual eth_out_if)::set(null, "uvm_test_top.env.out_mon", "vif", out);
        run_test();
    end
endmodule
