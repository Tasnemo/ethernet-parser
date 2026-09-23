module full_parser #(
    parameter int MAX_IPV4_BYTES = 1500
    // full network stack
) (
    input logic rx_clk,
    input logic rst,

    // GMII input interface
    input logic [7:0] rxd,
    input logic rx_dv,
    input logic rx_er,

    // parser feedback
    output logic parser_valid,
    output logic parser_start,
    output logic parser_last,
    output logic parser_error,
    output logic [7:0] parser
);

    assign parser       = '0;
    assign parser_valid = 1'b0;
    assign parser_start = 1'b0;
    assign parser_last  = 1'b0;
    assign parser_error = 1'b0;

endmodule
