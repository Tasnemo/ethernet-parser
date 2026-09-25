interface stream_if (input logic clk);
    logic rst;
    logic [7:0] data;
    logic data_valid;
    logic data_start;
    logic data_last;
    logic data_end;
    logic data_error;
    logic pseudo_valid;

    clocking drv_cb @(posedge clk);
        default input #1step output #1;
        output data, data_valid, data_start, data_last, data_end, data_error, pseudo_valid;
    endclocking

    clocking mon_cb @(posedge clk);
        default input #1step;
        input rst, data, data_valid, data_start, data_last, data_end, data_error, pseudo_valid;
    endclocking
endinterface
