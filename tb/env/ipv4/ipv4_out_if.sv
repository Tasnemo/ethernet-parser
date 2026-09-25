interface ipv4_out_if (input logic clk);
    logic [7:0] o_stream;
    logic header_ipv4_valid;
    logic total_length_valid;
    logic protocol_valid;
    logic source_ip_valid;
    logic destination_ip_valid;
    logic payload_ipv4_valid;
    logic start_of_packet;
    logic end_of_payload;
    logic end_of_packet;
    logic header_checksum_error;
    logic ipv4_error;

    clocking mon_cb @(posedge clk);
        default input #1step;
        input o_stream, header_ipv4_valid, total_length_valid, protocol_valid,
              source_ip_valid, destination_ip_valid, payload_ipv4_valid,
              start_of_packet, end_of_payload, end_of_packet,
              header_checksum_error, ipv4_error;
    endclocking
endinterface
