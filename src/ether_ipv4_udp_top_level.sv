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

    // first payload byte seen
    logic ether_started;

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

    // start flag resets every frame
    always_ff @(posedge rx_clk) begin
        if (rst) begin
            ether_started <= 1'b0;
        end else begin
            if (ether_start_of_packet) begin
                ether_started <= 1'b0;
            end

            if (parser_start) begin
                ether_started <= 1'b1;
            end

            if (ether_end_of_packet) begin
                ether_started <= 1'b0;
            end
        end
    end

    // ethernet payload out with fcs already stripped
    assign parser       = ether_stream;
    assign parser_valid = ether_payload_valid;
    assign parser_start = ether_payload_valid && !ether_started;
    // payload length is unknown until the ipv4 stage
    assign parser_last  = 1'b0;
    assign parser_error = ether_error;

endmodule
