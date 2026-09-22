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
    localparam logic [15:0] UDP_PROTOCOL = 16'h0011;

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

    // destination port high byte was zero
    logic port_high_zero;

    // checksum storage
    logic [15:0] checksum_sum;
    logic pseudo_low;
    logic payload_low;
    logic checksum_zero;

    // current byte checks
    logic packet_context;
    logic header_byte_active;
    logic segment_byte_active;
    logic [15:0] length_candidate;
    logic length_error_now;
    logic payload_complete_now;
    logic length_mismatch_now;
    logic port_error_now;
    logic structural_error_now;
    logic upstream_error_now;
    logic truncation_error_now;
    logic packet_error_now;
    logic output_abort;

    // checksum entities
    logic checksum_byte_high;
    logic [15:0] checksum_byte_sum;
    logic [15:0] checksum_next;
    logic checksum_skip_now;
    logic checksum_error_now;

    // keep the configured size inside the udp length field
    generate
        if ((MAX_UDP_BYTES < UDP_HEADER_BYTES)
            || (MAX_UDP_BYTES > 65535)) begin : invalid_max_udp_bytes
            initial $fatal(1, "MAX_UDP_BYTES must be between 8 and 65535");
        end
    endgenerate

    // ones complement add with end around carry
    function automatic logic [15:0] checksum_add_word(
        input logic [15:0] sum,
        input logic [15:0] word
    );
        logic [16:0] addition;
        begin
            addition = {1'b0, sum} + {1'b0, word};
            checksum_add_word = addition[15:0] + addition[16];
        end
    endfunction

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

    // destination port 0 is reserved so nothing can listen on it
    assign port_error_now = (stage == HEADER) && data_valid
                          && (header_index == 3'd3)
                          && port_high_zero && (data == 8'h00);

    // checksum covers the pseudo header, udp header, and payload
    // sum starts at the protocol number and picks up the ip
    // addresses in idle before the segment arrives
    assign checksum_byte_high = header_byte_active ? !header_index[0]
                              : (stage == IDLE)    ? !pseudo_low
                              :                      !payload_low;
    assign checksum_byte_sum = checksum_add_word(
        checksum_sum,
        checksum_byte_high ? {data, 8'b0} : {8'b0, data}
    );
    // udp length is in the header and the pseudo header
    assign checksum_next = ((stage == HEADER) && (header_index == 3'd5))
                         ? checksum_add_word(checksum_byte_sum,
                                             length_candidate)
                         : checksum_byte_sum;

    // zero checksum field means the sender skipped it
    assign checksum_skip_now = ((stage == HEADER) && (header_index == 3'd7))
                             ? (checksum_zero && (data == 8'h00))
                             : checksum_zero;
    // odd payload pads low with zero so the sum is already done
    assign checksum_error_now = payload_complete_now && !checksum_skip_now
                              && (checksum_next != 16'hFFFF);

    assign structural_error_now = length_error_now || length_mismatch_now
                                || port_error_now;

    // pass stream errors through anywhere inside the packet
    assign upstream_error_now = packet_context && data_error;
    // early data_end means truncated packet
    assign truncation_error_now = data_end && packet_context
                                && (stage != WAIT_END) && (stage != DROP)
                                && !payload_complete_now;

    assign packet_error_now = structural_error_now
                            || checksum_error_now
                            || upstream_error_now
                            || truncation_error_now;

    // earlier bytes stay speculative and later bytes stop on error
    assign output_abort = (stage == DROP) || upstream_error_now;
    assign udp_error = (stage == DROP) || packet_error_now;

    // packet framing signals
    assign start_of_packet = data_start && data_valid;
    assign end_of_packet = data_end && packet_context;

    // field windows
    // index is 0 in idle so byte 0 decodes the same way
    assign header_udp_valid = header_byte_active && !output_abort; // bytes 0-7
    assign source_port_valid = header_udp_valid
                             && (header_index[2:1] == 2'd0);      // bytes 0-1
    assign destination_port_valid = header_udp_valid
                                  && (header_index[2:1] == 2'd1); // bytes 2-3
    assign length_valid = header_udp_valid
                        && (header_index[2:1] == 2'd2);           // bytes 4-5
    assign checksum_valid = header_udp_valid
                          && (header_index[2:1] == 2'd3);         // bytes 6-7
    assign payload_udp_valid = (stage == PAYLOAD) && data_valid
                             && (bytes_remaining != 0) && !output_abort;

    // udp length marks the last segment byte
    assign end_of_payload = payload_complete_now && !output_abort;

    assign udp_checksum_error = checksum_error_now;

// parsing process
    always_ff @(posedge clk) begin
        if (rst) begin
            stage           <= IDLE;
            header_index    <= '0;
            length_high     <= '0;
            bytes_remaining <= '0;
            port_high_zero  <= 1'b0;
            checksum_sum    <= UDP_PROTOCOL;
            pseudo_low      <= 1'b0;
            payload_low     <= 1'b0;
            checksum_zero   <= 1'b0;
        end else begin
            case (stage)
                IDLE: begin
                    header_index    <= '0;
                    length_high     <= '0;
                    bytes_remaining <= '0;
                    port_high_zero  <= 1'b0;
                    payload_low     <= 1'b0;
                    checksum_zero   <= 1'b0;

                    if (pseudo_valid) begin
                        // source and destination ip in network order
                        checksum_sum <= checksum_next;
                        pseudo_low   <= !pseudo_low;
                    end

                    if (data_start && data_valid) begin
                        // byte 0 starts the header
                        checksum_sum <= checksum_next;
                        header_index <= 3'd1;
                        stage        <= HEADER;
                    end else begin
                        stage <= IDLE;
                    end
                end

                HEADER: begin
                    if (data_valid) begin
                        checksum_sum <= checksum_next;

                        if (header_index == 3'd2) begin
                            // destination port high byte
                            port_high_zero <= (data == 8'h00);
                        end

                        if (header_index == 3'd4) begin
                            // udp length high byte
                            length_high <= data;
                        end

                        if ((header_index == 3'd5) && !length_error_now) begin
                            // udp length low byte
                            bytes_remaining <= length_candidate - 16'd8;
                        end

                        if (header_index == 3'd6) begin
                            // checksum high byte
                            checksum_zero <= (data == 8'h00);
                        end

                        if (header_index == 3'd7) begin
                            // checksum low byte
                            checksum_zero <= checksum_zero && (data == 8'h00);
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
                        checksum_sum <= checksum_next;
                        payload_low  <= !payload_low;

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
                    // hold error through the packet boundary
                    stage <= DROP;
                end

                default: stage <= IDLE;
            endcase

            // structural, checksum, stream, or truncation error to drop
            if (packet_error_now) begin
                stage <= DROP;
            end

            // every frame boundary restarts the pseudo header sum
            if (data_end) begin
                checksum_sum <= UDP_PROTOCOL;
                pseudo_low   <= 1'b0;
            end

            // packet boundary has final priority
            if (data_end && packet_context) begin
                stage           <= IDLE;
                header_index    <= '0;
                length_high     <= '0;
                bytes_remaining <= '0;
                port_high_zero  <= 1'b0;
                payload_low     <= 1'b0;
                checksum_zero   <= 1'b0;
            end
        end
    end

endmodule
