module ethernet_parser (
// purely data link layer

input logic clk,
input logic rst,
// GMII data stream post PHY
input logic data[7:0],

//downstream payload send
output logic payload_ether,
output logic payload_ether_valid
// ethertype send for routing
output logic[15:0] ethertype,
output logic ethertype_valid

// progress checking
output logic eof,
output logic sof,

// errors
input logic rx_error
output logic ether_error
);
typedef enum logic[2:0] {IDLE, DEST_MAC, SOUR_MAC. ETHER_TYPE,  PAYLOAD, FCS  } protocol_stages
protocol_stages read;


always_ff begin
    if(rst) then 
        read <= IDLE;
        

end
endmodule
