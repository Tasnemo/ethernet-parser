module tb_top;
    import uvm_pkg::*;
    import top_env_pkg::*;

    logic clk = 1'b0;
    always #4ns clk = ~clk;

    gmii_if gmii (clk);
    parser_if out (clk);

    assign out.frame_dv = gmii.rx_dv;

    full_parser #(
        .MAX_IPV4_BYTES(1500)
    ) dut (
        .rx_clk(clk),
        .rst(gmii.rst),
        .rxd(gmii.rxd),
        .rx_dv(gmii.rx_dv),
        .rx_er(gmii.rx_er),
        .parser_valid(out.parser_valid),
        .parser_start(out.parser_start),
        .parser_last(out.parser_last),
        .parser_error(out.parser_error),
        .parser(out.parser)
    );

    initial begin
        gmii.rst = 1'b1;
        repeat (5) @(posedge clk);
        gmii.rst <= 1'b0;
    end

    initial begin
        uvm_config_db #(virtual gmii_if)::set(null, "uvm_test_top.env.agent*", "vif", gmii);
        uvm_config_db #(virtual parser_if)::set(null, "uvm_test_top.env.out_mon", "vif", out);
        run_test();
    end
endmodule
