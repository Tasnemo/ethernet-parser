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

    // ethernet stage
    logic [7:0] ether_stream;
    logic ether_dest_mac_valid;
    logic ether_sour_mac_valid;
    logic ether_payload_valid;
    logic ether_ethertype_valid;
    logic ether_end_of_packet;
    logic ether_start_of_packet;
    logic ether_fcs_error;
    logic ether_error;

    // ipv4 routing
    logic [7:0] ethertype_high;
    logic ethertype_half;
    logic route_ipv4;
    logic ipv4_started;

    logic ipv4_data_valid;
    logic ipv4_data_start;
    logic ipv4_data_end;
    logic ipv4_data_error;

    // ipv4 stage
    logic [7:0] ipv4_stream;
    logic ipv4_header_valid;
    logic ipv4_total_length_valid;
    logic ipv4_protocol_valid;
    logic ipv4_source_ip_valid;
    logic ipv4_destination_ip_valid;
    logic ipv4_payload_valid;
    logic ipv4_start_of_packet;
    logic ipv4_end_of_payload;
    logic ipv4_end_of_packet;
    logic ipv4_checksum_error;
    logic ipv4_error;

    // udp routing
    logic route_udp;
    logic udp_started;

    logic udp_data_valid;
    logic udp_data_start;
    logic udp_data_last;
    logic udp_data_end;
    logic udp_data_error;
    logic udp_pseudo_valid;

    // udp stage
    logic [7:0] udp_stream;
    logic udp_header_valid;
    logic udp_source_port_valid;
    logic udp_destination_port_valid;
    logic udp_length_valid;
    logic udp_checksum_valid;
    logic udp_payload_valid;
    logic udp_start_of_packet;
    logic udp_end_of_payload;
    logic udp_end_of_packet;
    logic udp_checksum_error;
    logic udp_error;

    // first payload byte seen
    logic payload_started;

    ethernet_parser ethernet (
        .rx_clk(rx_clk),
        .rst(rst),
        .rxd(rxd),
        .rx_dv(rx_dv),
        .rx_er(rx_er),
        .o_stream(ether_stream),
        .dest_mac_valid(ether_dest_mac_valid),
        .sour_mac_valid(ether_sour_mac_valid),
        .payload_ether_valid(ether_payload_valid),
        .ethertype_valid(ether_ethertype_valid),
        .end_of_packet(ether_end_of_packet),
        .start_of_packet(ether_start_of_packet),
        .fcs_error(ether_fcs_error),
        .ether_error(ether_error)
    );

    // routing and start flags reset every frame
    always_ff @(posedge rx_clk) begin
        if (rst) begin
            ethertype_high  <= '0;
            ethertype_half  <= 1'b0;
            route_ipv4      <= 1'b0;
            ipv4_started    <= 1'b0;
            route_udp       <= 1'b0;
            udp_started     <= 1'b0;
            payload_started <= 1'b0;
        end else begin
            if (ether_start_of_packet) begin
                ethertype_high  <= '0;
                ethertype_half  <= 1'b0;
                route_ipv4      <= 1'b0;
                ipv4_started    <= 1'b0;
                route_udp       <= 1'b0;
                udp_started     <= 1'b0;
                payload_started <= 1'b0;
            end

            // ethertype is big endian and finishes one cycle before payload
            if (ether_ethertype_valid) begin
                if (!ethertype_half) begin
                    ethertype_high <= ether_stream;
                    ethertype_half <= 1'b1;
                end else begin
                    route_ipv4     <= ({ethertype_high, ether_stream} == 16'h0800);
                    ethertype_half <= 1'b0;
                end
            end

            // protocol on byte 9 lands before the ip addresses
            if (ipv4_protocol_valid) begin
                route_udp <= (ipv4_stream == 8'd17);
            end

            if (ipv4_data_start) begin
                ipv4_started <= 1'b1;
            end

            if (udp_data_start) begin
                udp_started <= 1'b1;
            end

            if (parser_start) begin
                payload_started <= 1'b1;
            end

            if (ether_end_of_packet) begin
                ethertype_half  <= 1'b0;
                route_ipv4      <= 1'b0;
                ipv4_started    <= 1'b0;
                route_udp       <= 1'b0;
                udp_started     <= 1'b0;
                payload_started <= 1'b0;
            end
        end
    end

    // ipv4 packet is the ethernet payload of an 0x0800 frame
    assign ipv4_data_valid = ether_payload_valid && route_ipv4;
    assign ipv4_data_start = ipv4_data_valid && !ipv4_started;
    assign ipv4_data_end   = ether_end_of_packet && route_ipv4;
    assign ipv4_data_error = ether_error && route_ipv4;

    ipv4_parser #(
        .MAX_IPV4_BYTES(MAX_IPV4_BYTES)
    ) ipv4 (
        .clk(rx_clk),
        .rst(rst),
        .data(ether_stream),
        .data_valid(ipv4_data_valid),
        .data_start(ipv4_data_start),
        .data_end(ipv4_data_end),
        .data_error(ipv4_data_error),
        .o_stream(ipv4_stream),
        .header_ipv4_valid(ipv4_header_valid),
        .total_length_valid(ipv4_total_length_valid),
        .protocol_valid(ipv4_protocol_valid),
        .source_ip_valid(ipv4_source_ip_valid),
        .destination_ip_valid(ipv4_destination_ip_valid),
        .payload_ipv4_valid(ipv4_payload_valid),
        .start_of_packet(ipv4_start_of_packet),
        .end_of_payload(ipv4_end_of_payload),
        .end_of_packet(ipv4_end_of_packet),
        .header_checksum_error(ipv4_checksum_error),
        .ipv4_error(ipv4_error)
    );

    // udp segment is the ipv4 payload of a protocol 17 packet
    assign udp_data_valid   = ipv4_payload_valid && route_udp;
    assign udp_data_start   = udp_data_valid && !udp_started;
    // total length marks the last segment byte
    assign udp_data_last    = ipv4_end_of_payload && udp_data_valid;
    assign udp_data_end     = ipv4_end_of_packet && route_udp;
    assign udp_data_error   = ipv4_error && route_udp;
    // ip addresses feed the pseudo header before the segment starts
    assign udp_pseudo_valid = (ipv4_source_ip_valid || ipv4_destination_ip_valid)
                            && route_udp;

    udp_parser #(
        .MAX_UDP_BYTES(MAX_IPV4_BYTES - 20)
    ) udp (
        .clk(rx_clk),
        .rst(rst),
        .data(ipv4_stream),
        .data_valid(udp_data_valid),
        .data_start(udp_data_start),
        .data_last(udp_data_last),
        .data_end(udp_data_end),
        .data_error(udp_data_error),
        .pseudo_valid(udp_pseudo_valid),
        .o_stream(udp_stream),
        .header_udp_valid(udp_header_valid),
        .source_port_valid(udp_source_port_valid),
        .destination_port_valid(udp_destination_port_valid),
        .length_valid(udp_length_valid),
        .checksum_valid(udp_checksum_valid),
        .payload_udp_valid(udp_payload_valid),
        .start_of_packet(udp_start_of_packet),
        .end_of_payload(udp_end_of_payload),
        .end_of_packet(udp_end_of_packet),
        .udp_checksum_error(udp_checksum_error),
        .udp_error(udp_error)
    );

    // udp payload out with datagram framing
    assign parser       = udp_stream;
    assign parser_valid = udp_payload_valid;
    assign parser_start = udp_payload_valid && !payload_started;
    // udp length marks the last payload byte
    assign parser_last  = udp_end_of_payload && udp_payload_valid;
    assign parser_error = ether_error || ipv4_error || udp_error;

endmodule
