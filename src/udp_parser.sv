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
    localparam int LENGTH_WIDTH = (MAX_UDP_BYTES < UDP_HEADER_BYTES) ? 4
                                : (MAX_UDP_BYTES > 65535) ? 16
                                : $clog2(MAX_UDP_BYTES + 1);
    localparam logic [15:0] MAX_UDP_VALUE = MAX_UDP_BYTES;
    localparam logic [15:0] UDP_PROTOCOL = 16'h0011;

    // protocol stages
    // cursor doubles as header count and state
    localparam logic [3:0] CURSOR_IDLE       = 4'd0;
    localparam logic [3:0] CURSOR_PAYLOAD    = 4'd8;
    localparam logic [3:0] CURSOR_WAIT_END   = 4'd9;
    localparam logic [3:0] CURSOR_DROP       = 4'd10;
    localparam logic [3:0] CURSOR_LENGTH_BAD = 4'd11;
    localparam logic [LENGTH_WIDTH-1:0] TERMINAL_COUNT = 7;

    // header position and protocol stage share the cursor
    logic [3:0] cursor;

    // udp length storage
    logic [LENGTH_WIDTH-1:0] bytes_remaining;

    // checksum storage
    logic [15:0] checksum_sum;
    logic low_half;

    // port high byte zero then checksum zero
    logic field_zero;

    // current byte checks
    logic packet_context;
    logic header_cursor_active;
    logic header_byte_active;
    logic segment_byte_active;
    logic length_prefix_too_large;
    logic [15:0] length_candidate;
    logic checksum_byte_high;
    logic [15:0] checksum_word;
    logic [15:0] checksum_next;

    logic length_error_now;
    logic payload_complete_now;
    logic length_mismatch_now;
    logic port_error_now;
    logic checksum_skip_now;
    logic checksum_error_now;
    logic truncation_error_now;
    logic upstream_error_now;
    logic local_error_now;
    logic output_abort;

    // parameter check
    generate
        if ((MAX_UDP_BYTES < UDP_HEADER_BYTES)
            || (MAX_UDP_BYTES > 65535)) begin : invalid_max_udp_bytes
            initial begin
                $fatal(1);
            end
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

    // stream position
    assign o_stream = data;

    assign packet_context = (cursor != CURSOR_IDLE)
                          || (data_start && data_valid);
    assign header_cursor_active = ((cursor > CURSOR_IDLE)
                                && (cursor < CURSOR_PAYLOAD))
                               || (cursor == CURSOR_LENGTH_BAD);
    assign header_byte_active = data_valid
                              && (((cursor == CURSOR_IDLE) && data_start)
                               || header_cursor_active);
    assign segment_byte_active = header_byte_active
                               || ((cursor == CURSOR_PAYLOAD) && data_valid);

    // stash length high bits in the remaining counter
    // state 11 remembers overflow until byte 5
    assign length_prefix_too_large = (cursor == 4'd4) && data_valid
                                   && ({data, 8'b0} > MAX_UDP_VALUE);
    assign length_candidate = {{(16 - LENGTH_WIDTH){1'b0}}, bytes_remaining}
                            + data;

    // header bytes take their half from the cursor
    // pseudo and payload bytes share one toggle
    assign checksum_byte_high = header_byte_active ? !cursor[0] : !low_half;
    assign checksum_word = checksum_byte_high ? {data, 8'b0} : {8'b0, data};

    // length counts in the header and pseudo header
    // doubling is a left rotate in ones complement
    assign checksum_next = checksum_add_word(
        checksum_sum,
        (cursor[3:1] == 3'b010) ? {checksum_word[14:0], checksum_word[15]}
                                : checksum_word
    );

    assign length_error_now = data_valid
                            && ((cursor == CURSOR_LENGTH_BAD)
                             || ((cursor == 4'd5)
                              && ((length_candidate < 16'd8)
                               || (length_candidate > MAX_UDP_VALUE))));

    // counter is loaded with the full length so 7 marks the last byte
    assign payload_complete_now = data_valid
                                && ((cursor == CURSOR_PAYLOAD)
                                 || (cursor == 4'd7))
                                && (bytes_remaining == TERMINAL_COUNT);

    assign length_mismatch_now = segment_byte_active
                               && (data_last != payload_complete_now);

    assign port_error_now = (cursor == 4'd3) && data_valid
                          && field_zero && (data == 8'h00);

    assign checksum_skip_now = field_zero
                             && ((cursor != 4'd7) || (data == 8'h00));
    assign checksum_error_now = payload_complete_now && !checksum_skip_now
                              && (checksum_next != 16'hFFFF);

    assign truncation_error_now = data_end && packet_context
                                && (cursor != CURSOR_WAIT_END)
                                && (cursor != CURSOR_DROP)
                                && !payload_complete_now;
    assign upstream_error_now = packet_context && data_error;
    assign local_error_now = length_error_now || length_mismatch_now
                           || port_error_now || checksum_error_now
                           || truncation_error_now;

    assign output_abort = (cursor == CURSOR_DROP) || upstream_error_now;

    // packet signals
    assign start_of_packet = data_start && data_valid;
    assign end_of_packet = data_end && packet_context;
    assign udp_checksum_error = checksum_error_now;
    assign udp_error = (cursor == CURSOR_DROP)
                     || upstream_error_now || local_error_now;

    // field windows line up with the current byte
    assign header_udp_valid = header_byte_active && !output_abort;
    assign source_port_valid = header_udp_valid
                             && (cursor[3:1] == 3'b000);
    assign destination_port_valid = header_udp_valid
                                  && (cursor[3:1] == 3'b001);
    assign length_valid = header_udp_valid
                        && ((cursor[3:1] == 3'b010)
                         || (cursor == CURSOR_LENGTH_BAD));
    assign checksum_valid = header_udp_valid
                          && (cursor[3:1] == 3'b011);
    assign payload_udp_valid = (cursor == CURSOR_PAYLOAD) && data_valid
                             && !output_abort;

    assign end_of_payload = payload_complete_now && !output_abort;

    // parsing process
    always_ff @(posedge clk) begin
        if (rst) begin
            cursor          <= CURSOR_IDLE;
            bytes_remaining <= '0;
            checksum_sum    <= UDP_PROTOCOL;
            low_half        <= 1'b0;
            field_zero      <= 1'b0;
        end else begin
            if (cursor == CURSOR_IDLE) begin
                cursor          <= CURSOR_IDLE;
                bytes_remaining <= '0;
                field_zero      <= 1'b0;

                if (pseudo_valid) begin
                    checksum_sum <= checksum_next;
                    low_half     <= !low_half;
                end

                if (data_start && data_valid) begin
                    checksum_sum <= checksum_next;
                    if (length_mismatch_now) begin
                        cursor <= CURSOR_DROP;
                    end else begin
                        cursor <= 4'd1;
                    end
                end
            end else if (header_cursor_active) begin
                if (data_valid) begin
                    checksum_sum <= checksum_next;

                    if ((cursor == 4'd2) || (cursor == 4'd6)) begin
                        field_zero <= (data == 8'h00);
                    end else if (cursor == 4'd7) begin
                        field_zero <= field_zero && (data == 8'h00);
                    end

                    if (cursor == 4'd4) begin
                        if (length_prefix_too_large) begin
                            cursor <= CURSOR_LENGTH_BAD;
                        end else begin
                            bytes_remaining <= {data, 8'b0};
                            cursor <= 4'd5;
                        end
                    end else if (cursor == CURSOR_LENGTH_BAD) begin
                        cursor <= CURSOR_DROP;
                    end else if (cursor == 4'd5) begin
                        if (length_error_now) begin
                            cursor <= CURSOR_DROP;
                        end else begin
                            bytes_remaining <= length_candidate;
                            cursor <= 4'd6;
                        end
                    end else begin
                        if (cursor >= 4'd6) begin
                            bytes_remaining <= bytes_remaining - 1'b1;
                        end

                        if (cursor == 4'd7) begin
                            if (bytes_remaining == TERMINAL_COUNT) begin
                                cursor <= CURSOR_WAIT_END;
                            end else begin
                                cursor <= CURSOR_PAYLOAD;
                            end
                        end else begin
                            cursor <= cursor + 1'b1;
                        end
                    end
                end
            end else if (cursor == CURSOR_PAYLOAD) begin
                if (data_valid) begin
                    checksum_sum    <= checksum_next;
                    low_half        <= !low_half;
                    bytes_remaining <= bytes_remaining - 1'b1;
                    if (bytes_remaining == TERMINAL_COUNT) begin
                        cursor <= CURSOR_WAIT_END;
                    end
                end
            end else if (cursor == CURSOR_WAIT_END) begin
                cursor <= CURSOR_WAIT_END;
            end else begin
                cursor <= CURSOR_DROP;
            end

            if (local_error_now || upstream_error_now) begin
                cursor <= CURSOR_DROP;
            end

            if (data_end) begin
                checksum_sum <= UDP_PROTOCOL;
                low_half     <= 1'b0;
            end

            if (data_end && packet_context) begin
                cursor          <= CURSOR_IDLE;
                bytes_remaining <= '0;
                field_zero      <= 1'b0;
            end
        end
    end

endmodule
