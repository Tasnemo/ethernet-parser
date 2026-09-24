interface gmii_if (input logic clk);
    logic rst;
    logic [7:0] rxd;
    logic rx_dv;
    logic rx_er;

    // drive a little after the edge so the dut samples clean values
    clocking drv_cb @(posedge clk);
        default input #1step output #1;
        output rxd, rx_dv, rx_er;
    endclocking

    clocking mon_cb @(posedge clk);
        default input #1step;
        input rst, rxd, rx_dv, rx_er;
    endclocking
endinterface
