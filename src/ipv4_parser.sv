module ipv4_parser #(
    parameter int MAX_IPV4_BYTES = 1500
    // purely internet layer
) (
    // clock and reset
    input logic clk,
    input logic rst,

    // input stream
    input logic [7:0] data,
    input logic data_valid,
    input logic data_start,
    input logic data_end,
    input logic data_error,

    // output stream
    output logic [7:0] o_stream,

    //stage valid signals
    output logic header_ipv4_valid,
    output logic total_length_valid,
    output logic protocol_valid,
    output logic source_ip_valid,
    output logic destination_ip_valid,
    output logic payload_ipv4_valid,

    // progress checking
    output logic start_of_packet,
    output logic end_of_payload,
    output logic end_of_packet,

    // error output
    output logic header_checksum_error,
    output logic ipv4_error
);

    // general standards
    localparam int IPV4_HEADER_BYTES = 20;
    localparam int LENGTH_WIDTH = (MAX_IPV4_BYTES < IPV4_HEADER_BYTES) ? 5
                                : (MAX_IPV4_BYTES > 65535) ? 16
                                : $clog2(MAX_IPV4_BYTES + 1);
    localparam logic [15:0] MAX_IPV4_VALUE = MAX_IPV4_BYTES;

    // protocol stages
    // cursor doubles as header count and state
    // 5 cursor + 11 remaining + 16 checksum = 32 bits
    localparam logic [4:0] CURSOR_IDLE        = 5'd0;
    localparam logic [4:0] CURSOR_PAYLOAD     = 5'd20;
    localparam logic [4:0] CURSOR_WAIT_END    = 5'd21;
    localparam logic [4:0] CURSOR_DROP        = 5'd22;
    localparam logic [4:0] CURSOR_LENGTH_BAD  = 5'd23;
    localparam logic [LENGTH_WIDTH-1:0] TERMINAL_COUNT = 5;

    // header position and protocol stage share the cursor
    logic [4:0] cursor;

    // total length storage
    logic [LENGTH_WIDTH-1:0] bytes_remaining;

    // checksum storage
    logic [15:0] checksum_sum;

    // current byte checks
    logic packet_context;
    logic header_byte_active;
    logic header_cursor_active;
    logic [15:0] length_candidate;
    logic [15:0] checksum_next;

    logic version_ihl_error_now;
    logic length_prefix_too_large;
    logic length_error_now;
    logic fragment_error_now;
    logic checksum_error_now;
    logic truncation_error_now;
    logic upstream_error_now;
    logic local_error_now;
    logic output_abort;
    logic payload_complete_now;

    // parameter check
    generate
        if ((MAX_IPV4_BYTES < IPV4_HEADER_BYTES)
            || (MAX_IPV4_BYTES > 65535)) begin : invalid_max_ipv4_bytes
            initial begin
                $fatal(1);
            end
        end
    endgenerate

    // one byte through the checksum in network order
    function automatic logic [15:0] checksum_add_byte(
        input logic [15:0] sum,
        input logic [7:0] byte_value,
        input logic high_byte
    );
        logic [16:0] addition;
        begin
            if (high_byte) begin
                addition = {1'b0, sum} + {1'b0, byte_value, 8'b0};
            end else begin
                addition = {1'b0, sum} + {9'b0, byte_value};
            end
            checksum_add_byte = addition[15:0] + addition[16];
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

    // stash length high bits in the remaining counter
    // state 23 remembers overflow until byte 3
    assign length_prefix_too_large = (cursor == 5'd2) && data_valid
                                   && ({data, 8'b0} > MAX_IPV4_VALUE);
    assign length_candidate = {{(16 - LENGTH_WIDTH){1'b0}}, bytes_remaining}
                            + data;

    // next checksum value
    assign checksum_next = checksum_add_byte(
        checksum_sum,
        data,
        (cursor == CURSOR_IDLE) ? 1'b1 : !cursor[0]
    );

    assign version_ihl_error_now = (cursor == CURSOR_IDLE)
                                 && data_start && data_valid
                                 && ((data[7:4] != 4'h4)
                                  || (data[3:0] != 4'h5));

    assign length_error_now = data_valid
                            && ((cursor == CURSOR_LENGTH_BAD)
                             || ((cursor == 5'd3)
                              && ((length_candidate < 16'd20)
                               || (length_candidate > MAX_IPV4_VALUE))));

    // no reassembly so allow df and reject mf, reserved, or offset
    assign fragment_error_now = data_valid
                              && (((cursor == 5'd6)
                                && (data[7] || data[5] || (|data[4:0])))
                               || ((cursor == 5'd7) && (|data)));

    assign checksum_error_now = (cursor == 5'd19) && data_valid
                              && (checksum_next != 16'hFFFF);

    // counter is biased by 4 so 5 marks the last ipv4 byte
    assign payload_complete_now = ((cursor == CURSOR_PAYLOAD) && data_valid
                                && (bytes_remaining == TERMINAL_COUNT))
                               || ((cursor == 5'd19) && data_valid
                                && (bytes_remaining == TERMINAL_COUNT));

    assign truncation_error_now = data_end && packet_context
                                && (cursor != CURSOR_WAIT_END)
                                && (cursor != CURSOR_DROP)
                                && !payload_complete_now;
    assign upstream_error_now = packet_context && data_error;
    assign local_error_now = version_ihl_error_now || length_error_now
                           || fragment_error_now || checksum_error_now
                           || truncation_error_now;

    // local errors stop later bytes
    // data_error also kills the current byte
    assign output_abort = (cursor == CURSOR_DROP) || upstream_error_now;

    // packet signals
    assign start_of_packet = data_start && data_valid;
    assign end_of_packet = data_end && packet_context;
    assign header_checksum_error = checksum_error_now;
    assign ipv4_error = (cursor == CURSOR_DROP)
                      || upstream_error_now || local_error_now;

    // field windows line up with the current byte
    assign header_ipv4_valid = header_byte_active && !output_abort;
    assign total_length_valid = header_ipv4_valid
                              && ((cursor == 5'd2) || (cursor == 5'd3)
                               || (cursor == CURSOR_LENGTH_BAD));
    assign protocol_valid = header_ipv4_valid && (cursor == 5'd9);
    assign source_ip_valid = header_ipv4_valid
                           && (cursor[4:2] == 3'b011);
    assign destination_ip_valid = header_ipv4_valid
                                && (cursor[4:2] == 3'b100);
    assign payload_ipv4_valid = (cursor == CURSOR_PAYLOAD) && data_valid
                              && !output_abort;

    assign end_of_payload = !output_abort
                          && ((payload_ipv4_valid
                            && (bytes_remaining == TERMINAL_COUNT))
                           || ((cursor == 5'd19) && data_valid
                            && (bytes_remaining == TERMINAL_COUNT)));

    // parsing process
    always_ff @(posedge clk) begin
        if (rst) begin
            cursor          <= CURSOR_IDLE;
            bytes_remaining <= '0;
            checksum_sum    <= '0;
        end else begin
            if (cursor == CURSOR_IDLE) begin
                cursor          <= CURSOR_IDLE;
                bytes_remaining <= '0;
                checksum_sum    <= '0;

                if (data_start && data_valid) begin
                    checksum_sum <= {data, 8'b0};
                    if (version_ihl_error_now) begin
                        cursor <= CURSOR_DROP;
                    end else begin
                        cursor <= 5'd1;
                    end
                end
            end else if (header_cursor_active) begin
                if (data_valid) begin
                    checksum_sum <= checksum_next;

                    if (cursor == 5'd2) begin
                        if (length_prefix_too_large) begin
                            cursor <= CURSOR_LENGTH_BAD;
                        end else begin
                            bytes_remaining <= {data, 8'b0};
                            cursor <= 5'd3;
                        end
                    end else if (cursor == CURSOR_LENGTH_BAD) begin
                        cursor <= CURSOR_DROP;
                    end else if (cursor == 5'd3) begin
                        if (length_error_now) begin
                            cursor <= CURSOR_DROP;
                        end else begin
                            bytes_remaining <= length_candidate;
                            cursor <= 5'd4;
                        end
                    end else begin
                        if (cursor >= 5'd4) begin
                            bytes_remaining <= bytes_remaining - 1'b1;
                        end

                        if (fragment_error_now || checksum_error_now) begin
                            cursor <= CURSOR_DROP;
                        end else if (cursor == 5'd19) begin
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
                    bytes_remaining <= bytes_remaining - 1'b1;
                    if (bytes_remaining == TERMINAL_COUNT) begin
                        cursor <= CURSOR_WAIT_END;
                    end
                end
            end else if (cursor == CURSOR_WAIT_END) begin
                // drain ethernet padding
                cursor <= CURSOR_WAIT_END;
            end else begin
                // drop and unused states fail closed
                cursor <= CURSOR_DROP;
            end

            if (upstream_error_now) begin
                cursor <= CURSOR_DROP;
            end

            // data_end wins so drop cannot stick
            if (data_end && packet_context) begin
                cursor          <= CURSOR_IDLE;
                bytes_remaining <= '0;
                checksum_sum    <= '0;
            end
        end
    end

endmodule
