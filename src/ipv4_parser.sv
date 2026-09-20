module ipv4_parser #(
    parameter int MAX_IPV4_BYTES = 1500
) (
    // clock and reset
    input  logic       clk,
    input  logic       rst,

    // input stream
    input  logic [7:0] data,
    input  logic       data_valid,
    input  logic       data_start,
    input  logic       data_end,
    input  logic       data_error,

    // output stream
    output logic [7:0] o_stream,

    //stage valid signals
    output logic       header_ipv4_valid,
    output logic       total_length_valid,
    output logic       protocol_valid,
    output logic       source_ip_valid,
    output logic       destination_ip_valid,
    output logic       payload_ipv4_valid,

    // progress checking
    output logic       start_of_packet,
    output logic       end_of_payload,
    output logic       end_of_packet,

    // error output
    output logic       header_checksum_error,
    output logic       ipv4_error
);

    // general standards
    localparam int IPV4_HEADER_BYTES = 20;
    localparam int LENGTH_WIDTH = (MAX_IPV4_BYTES < IPV4_HEADER_BYTES)
                                ? 5 : $clog2(MAX_IPV4_BYTES + 1);
    localparam logic [15:0] MAX_IPV4_VALUE = MAX_IPV4_BYTES;

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
    logic [4:0] header_index;

    // total length storage
    logic [7:0] length_high;
    logic [LENGTH_WIDTH-1:0] bytes_remaining;

    // current byte checks
    logic packet_context;
    logic header_byte_active;
    logic [15:0] length_candidate;
    logic version_ihl_error_now;
    logic length_error_now;
    logic structural_error_now;
    logic upstream_error_now;
    logic payload_complete_now;
    logic truncation_error_now;
    logic packet_error_now;
    logic output_abort;

    // keep the configured size inside the ipv4 length field
    generate
        if ((MAX_IPV4_BYTES < IPV4_HEADER_BYTES)
            || (MAX_IPV4_BYTES > 65535)) begin : invalid_max_ipv4_bytes
            initial $fatal(1, "MAX_IPV4_BYTES must be between 20 and 65535");
        end
    endgenerate

    // output stream
    assign o_stream = data;

    // header entities
    assign packet_context = (stage != IDLE) || (data_start && data_valid);
    assign header_byte_active = data_valid
                              && (((stage == IDLE) && data_start)
                               || (stage == HEADER));
    assign length_candidate = {length_high, data};

    // version and ihl on byte 0
    assign version_ihl_error_now = (stage == IDLE) && data_start && data_valid
                                 && ((data[7:4] != 4'h4)
                                  || (data[3:0] != 4'h5));

    // total length ends on byte 3
    assign length_error_now = (stage == HEADER) && data_valid
                            && (header_index == 5'd3)
                            && ((length_candidate < 16'd20)
                             || (length_candidate > MAX_IPV4_VALUE));

    assign structural_error_now = version_ihl_error_now || length_error_now;

    // legal end on byte 19 with no payload or on the last payload byte
    assign payload_complete_now = ((stage == PAYLOAD) && data_valid
                                && (bytes_remaining == 1))
                               || ((stage == HEADER) && data_valid
                                && (header_index == 5'd19)
                                && (bytes_remaining == 0));

    // pass stream errors through anywhere inside the packet
    assign upstream_error_now = packet_context && data_error;
    // early data_end means truncated packet
    assign truncation_error_now = data_end && packet_context
                                && (stage != WAIT_END) && (stage != DROP)
                                && !payload_complete_now;

    assign packet_error_now = structural_error_now
                            || upstream_error_now
                            || truncation_error_now;

    // earlier bytes stay speculative and later bytes stop on error
    assign output_abort = (stage == DROP) || upstream_error_now;
    assign ipv4_error = (stage == DROP) || packet_error_now;

    // packet framing signals
    assign start_of_packet = data_start && data_valid;
    assign end_of_packet = data_end && packet_context;

    // field windows
    assign header_ipv4_valid = header_byte_active && !output_abort;
    assign total_length_valid = header_ipv4_valid && (stage == HEADER)
                              && ((header_index == 5'd2)
                               || (header_index == 5'd3)); // bytes 2-3
    assign protocol_valid = header_ipv4_valid && (stage == HEADER)
                          && (header_index == 5'd9);       // byte 9
    assign source_ip_valid = header_ipv4_valid && (stage == HEADER)
                           && (header_index >= 5'd12)
                           && (header_index <= 5'd15);     // bytes 12-15
    assign destination_ip_valid = header_ipv4_valid && (stage == HEADER)
                                && (header_index >= 5'd16)
                                && (header_index <= 5'd19); // bytes 16-19
    assign payload_ipv4_valid = (stage == PAYLOAD) && data_valid
                              && (bytes_remaining != 0) && !output_abort;

    assign end_of_payload = !output_abort
                          && ((payload_ipv4_valid && (bytes_remaining == 1))
                           || ((stage == HEADER) && data_valid
                            && (header_index == 5'd19)
                            && (bytes_remaining == 0)));

    assign header_checksum_error = 1'b0;

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
                        header_index <= 5'd1;
                        if (version_ihl_error_now) begin
                            stage <= DROP;
                        end else begin
                            stage <= HEADER;
                        end
                    end else begin
                        stage <= IDLE;
                    end
                end

                HEADER: begin
                    if (data_valid) begin
                        if (header_index == 5'd2) begin
                            length_high <= data;
                        end

                        if ((header_index == 5'd3) && !length_error_now) begin
                            bytes_remaining <= length_candidate - 16'd20;
                        end

                        if (length_error_now) begin
                            stage <= DROP;
                        end else if (header_index == 5'd19) begin
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
                        if (bytes_remaining > 1) begin
                            bytes_remaining <= bytes_remaining - 1'b1;
                        end else begin
                            bytes_remaining <= '0;
                            stage           <= WAIT_END;
                        end
                    end
                end

                WAIT_END: begin
                    // ignore ethernet padding after ipv4 payload
                    stage <= WAIT_END;
                end

                DROP: begin
                    // hold error through the packet boundary
                    stage <= DROP;
                end

                default: stage <= IDLE;
            endcase

            // pass stream or truncation error to drop
            if (packet_error_now) begin
                stage <= DROP;
            end

            // packet boundary has final priority
            if (data_end && packet_context) begin
                stage           <= IDLE;
                header_index    <= '0;
                length_high     <= '0;
                bytes_remaining <= '0;
            end
        end
    end

endmodule
