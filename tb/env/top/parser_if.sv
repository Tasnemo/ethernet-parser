interface parser_if (input logic clk);
    logic [7:0] parser;
    logic parser_valid;
    logic parser_start;
    logic parser_last;
    logic parser_error;

    // rx_dv from the wire marks which frame the outputs belong to
    logic frame_dv;

    clocking mon_cb @(posedge clk);
        default input #1step;
        input parser, parser_valid, parser_start, parser_last, parser_error, frame_dv;
    endclocking
endinterface
