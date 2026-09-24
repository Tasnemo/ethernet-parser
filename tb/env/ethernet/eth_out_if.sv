interface eth_out_if (input logic clk);
    logic [7:0] o_stream;
    logic dest_mac_valid;
    logic sour_mac_valid;
    logic payload_ether_valid;
    logic ethertype_valid;
    logic end_of_packet;
    logic start_of_packet;
    logic fcs_error;
    logic ether_error;

    clocking mon_cb @(posedge clk);
        default input #1step;
        input o_stream, dest_mac_valid, sour_mac_valid, payload_ether_valid,
              ethertype_valid, end_of_packet, start_of_packet, fcs_error, ether_error;
    endclocking
endinterface
