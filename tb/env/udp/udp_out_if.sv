interface udp_out_if (input logic clk);
    logic [7:0] o_stream;
    logic header_udp_valid;
    logic source_port_valid;
    logic destination_port_valid;
    logic length_valid;
    logic checksum_valid;
    logic payload_udp_valid;
    logic start_of_packet;
    logic end_of_payload;
    logic end_of_packet;
    logic udp_checksum_error;
    logic udp_error;

    clocking mon_cb @(posedge clk);
        default input #1step;
        input o_stream, header_udp_valid, source_port_valid, destination_port_valid,
              length_valid, checksum_valid, payload_udp_valid,
              start_of_packet, end_of_payload, end_of_packet,
              udp_checksum_error, udp_error;
    endclocking
endinterface
