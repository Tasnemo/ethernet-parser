module full_parser (
input logic rx_clk,
input logic rst,

// GMII input interface
input logic[7:0] rxd,
input logic rx_dv,
input logic rx_er,


// parser feedback
output logic parser_valid,
output logic parser_error,
output logic[7:0] parser



);


endmodule
