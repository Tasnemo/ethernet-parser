module full_parser (
input logic clk,
input logic rst,

// GMII output pins
input logic[7:0] gmii_rxd,
input logic gmii_rx_dv,
input logic gmii_rx_er,

// parser feedback
output logic parser_valid,
output logic parser_error,
output logic[7:0] parser



);


endmodule
