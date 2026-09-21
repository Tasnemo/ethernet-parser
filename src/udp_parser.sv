module udp_parser #(
    parameter int MAX_UDP_BYTES = 1480
    // purely transport layer
) (
    // clock and reset
    input  logic       clk,
    input  logic       rst,

    // input stream
    input  logic [7:0] data,
    input  logic       data_valid,
    input  logic       data_start,
    input  logic       data_last,
    input  logic       data_end,
    input  logic       data_error,

    // pseudo header bytes
    input  logic       pseudo_valid,

    // output stream
    output logic [7:0] o_stream,

    //stage valid signals
    output logic       header_udp_valid,
    output logic       source_port_valid,
    output logic       destination_port_valid,
    output logic       length_valid,
    output logic       checksum_valid,
    output logic       payload_udp_valid,

    // progress checking
    output logic       start_of_packet,
    output logic       end_of_payload,
    output logic       end_of_packet,

    // error output
    output logic       udp_checksum_error,
    output logic       udp_error
);

    // general standards
    localparam int UDP_HEADER_BYTES = 8;
    localparam int LENGTH_WIDTH = (MAX_UDP_BYTES < UDP_HEADER_BYTES)
                                ? 4 : $clog2(MAX_UDP_BYTES + 1);
    localparam logic [15:0] MAX_UDP_VALUE = MAX_UDP_BYTES;

    // protocol stages
    typedef enum logic [2:0] {
        IDLE,
        HEADER,
        PAYLOAD,
        WAIT_END,
        DROP
    } stage_t;

    stage_t stage;

    // header position
    logic [2:0] header_index;

    // udp length storage
    logic [7:0] length_high;
    logic [LENGTH_WIDTH-1:0] bytes_remaining;

    // header entities
    logic packet_context;
    logic header_byte_active;
    logic segment_byte_active;
    logic [15:0] length_candidate;
    logic length_error_now;
    logic payload_complete_now;
    logic length_mismatch_now;
    logic structural_error_now;
    logic discard_now;

    // keep the configured size inside the udp length field
    generate
        if ((MAX_UDP_BYTES < UDP_HEADER_BYTES)
            || (MAX_UDP_BYTES > 65535)) begin : invalid_max_udp_bytes
            initial $fatal(1, "MAX_UDP_BYTES must be between 8 and 65535");
        end
    endgenerate

    // output stream
    assign o_stream = data;

    // header entities
    assign packet_context = (stage != IDLE) || (data_start && data_valid);
    assign header_byte_active = data_valid
                              && (((stage == IDLE) && data_start)
                               || (stage == HEADER));
    assign segment_byte_active = header_byte_active
                               || ((stage == PAYLOAD) && data_valid);
    // udp length joins on byte 5
    assign length_candidate = {length_high, data};

    // udp length check on byte 5
    assign length_error_now = (stage == HEADER) && data_valid
                            && (header_index == 3'd5)
                            && ((length_candidate < 16'd8)
                             || (length_candidate > MAX_UDP_VALUE));

    // legal end on byte 7 with no payload or on the last payload byte
    assign payload_complete_now = ((stage == PAYLOAD) && data_valid
                                && (bytes_remaining == 1))
                               || ((stage == HEADER) && data_valid
                                && (header_index == 3'd7)
                                && (bytes_remaining == 0));

    // ipv4 payload end has to land on the udp length end
    assign length_mismatch_now = segment_byte_active
                               && (data_last != payload_complete_now);

    assign structural_error_now = length_error_now || length_mismatch_now;

    // drop stage holds the error through the packet
    assign discard_now = (stage == DROP) || structural_error_now;
    assign udp_error = discard_now;

    // packet framing signals
    assign start_of_packet = data_start && data_valid;
    assign end_of_packet = data_end && packet_context;

    // field windows
    // index is 0 in idle so byte 0 decodes the same way
    assign header_udp_valid = header_byte_active && !discard_now; // bytes 0-7
    assign source_port_valid = header_udp_valid
                             && (header_index[2:1] == 2'd0);      // bytes 0-1
    assign destination_port_valid = header_udp_valid
                                  && (header_index[2:1] == 2'd1); // bytes 2-3
    assign length_valid = header_udp_valid
                        && (header_index[2:1] == 2'd2);           // bytes 4-5
    assign checksum_valid = header_udp_valid
                          && (header_index[2:1] == 2'd3);         // bytes 6-7
    assign payload_udp_valid = (stage == PAYLOAD) && data_valid
                             && (bytes_remaining != 0) && !discard_now;

    // udp length marks the last segment byte
    assign end_of_payload = payload_complete_now && !discard_now;

    assign udp_checksum_error = 1'b0;

// parsing process
    always_ff @(posedge clk) begin
        if (rst) begin
            stage           <= IDLE;
            header_index    <= '0;
            length_high     <= '0;
            bytes_remaining <= '0;
        end else begin
            case (stage)
                IDLE: begin
                    header_index    <= '0;
                    length_high     <= '0;
                    bytes_remaining <= '0;

                    if (data_start && data_valid) begin
                        // byte 0 starts the header
                        header_index <= 3'd1;
                        stage        <= HEADER;
                    end else begin
                        stage <= IDLE;
                    end
                end

                HEADER: begin
                    if (data_valid) begin
                        if (header_index == 3'd4) begin
                            // udp length high byte
                            length_high <= data;
                        end

                        if ((header_index == 3'd5) && !length_error_now) begin
                            // udp length low byte
                            bytes_remaining <= length_candidate - 16'd8;
                        end

                        if (header_index == 3'd7) begin
                            // byte 7 ends the header
                            if (bytes_remaining == 0) begin
                                stage <= WAIT_END;
                            end else begin
                                stage <= PAYLOAD;
                            end
                        end else begin
                            header_index <= header_index + 1'b1;
                        end
                    end
                end

                PAYLOAD: begin
                    if (data_valid) begin
                        // count only accepted stream bytes
                        if (bytes_remaining > 1) begin
                            bytes_remaining <= bytes_remaining - 1'b1;
                        end else begin
                            bytes_remaining <= '0;
                            stage           <= WAIT_END;
                        end
                    end
                end

                WAIT_END: begin
                    // wait for the frame boundary
                    stage <= WAIT_END;
                end

                DROP: begin
                    // hold structural error until frame end
                    stage <= DROP;
                end

                default: stage <= IDLE;
            endcase

            // bad length or mismatched end goes to drop
            if (structural_error_now) begin
                stage <= DROP;
            end

            // frame boundary reset
            if (data_end && packet_context) begin
                stage           <= IDLE;
                header_index    <= '0;
                length_high     <= '0;
                bytes_remaining <= '0;
            end
        end
    end

endmodule
