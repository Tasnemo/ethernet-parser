module ipv4_parser (
    parameter int MAX_IPV4_BYTES = 1500
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
    localparam int LENGTH_WIDTH = (MAX_IPV4_BYTES < IPV4_HEADER_BYTES)
                                ? 5 : $clog2(MAX_IPV4_BYTES + 1);
    localparam logic [15:0] MAX_IPV4_VALUE = MAX_IPV4_BYTES;

    // protocol stages
    typedef enum logic [2:0] {IDLE, HEADER, PAYLOAD,
                              WAIT_END, DROP} protocol_stages;
    protocol_stages read;

    // header position
    logic [4:0] header_count;

    // total length storage
    logic [7:0] length_high;
    logic [LENGTH_WIDTH-1:0] bytes_remaining;

    // checksum and error storage
    logic [15:0] checksum_sum;
    logic err_latch;

    // current byte checks
    logic packet_context;
    logic header_byte_active;
    logic [15:0] length_candidate;
    logic [15:0] checksum_next;

    logic version_ihl_error_now;
    logic length_error_now;
    logic fragment_error_now;
    logic checksum_error_now;
    logic truncation_error_now;
    logic upstream_error_now;
    logic local_error_now;
    logic output_abort;
    logic payload_complete_now;

    // keep the configured size inside the ipv4 length field
    generate
        if ((MAX_IPV4_BYTES < IPV4_HEADER_BYTES)
            || (MAX_IPV4_BYTES > 65535)) begin : invalid_max_ipv4_bytes
            initial begin
                $fatal(1);
            end
        end
    endgenerate

    // one byte through checksum with end around carry
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

    // output stream
    assign o_stream = data;

    // header entities
    assign packet_context = (read != IDLE) || (data_start && data_valid);
    assign header_byte_active = data_valid
                              && (((read == IDLE) && data_start)
                               || (read == HEADER));

    assign length_candidate = {length_high, data};
    // even bytes fill the high half of each checksum word
    assign checksum_next = checksum_add_byte(
        checksum_sum,
        data,
        (read == IDLE) ? 1'b1 : !header_count[0]
    );

    // version and ihl on byte 0
    assign version_ihl_error_now = (read == IDLE) && data_start && data_valid
                                 && ((data[7:4] != 4'h4) || (data[3:0] != 4'h5));

    // total length ends on byte 3
    assign length_error_now = (read == HEADER) && data_valid
                            && (header_count == 5'd3)
                            && ((length_candidate < IPV4_HEADER_BYTES)
                             || (length_candidate > MAX_IPV4_VALUE));

    // flags and fragment offset on bytes 6-7
    // reserved mf and any offset are rejected while df is allowed
    assign fragment_error_now = (read == HEADER) && data_valid
                              && (((header_count == 5'd6)
                                && (data[7] || data[5] || (|data[4:0])))
                                || ((header_count == 5'd7) && (|data)));

    // all header words must sum to ones by byte 19
    assign checksum_error_now = (read == HEADER) && data_valid
                              && (header_count == 5'd19)
                              && (checksum_next != 16'hFFFF);

    // legal end on byte 19 with no payload or on the last payload byte
    assign payload_complete_now = ((read == PAYLOAD) && data_valid
                                && (bytes_remaining == 1))
                               || ((read == HEADER) && data_valid
                                && (header_count == 5'd19)
                                && (bytes_remaining == 0));

    // early data_end means truncated packet
    assign truncation_error_now = data_end && packet_context
                                && (read != WAIT_END) && (read != DROP)
                                && !payload_complete_now;

    // pass stream errors through anywhere inside the packet
    assign upstream_error_now = packet_context && data_error;
    assign local_error_now = version_ihl_error_now || length_error_now
                           || fragment_error_now || checksum_error_now
                           || truncation_error_now;
    assign output_abort = ((read != IDLE) && err_latch)
                        || upstream_error_now;

    // packet framing and error signals
    assign start_of_packet = data_start && data_valid;
    assign end_of_packet = data_end && packet_context;
    assign header_checksum_error = checksum_error_now;
    assign ipv4_error = (((read != IDLE) && err_latch)
                      || upstream_error_now || local_error_now);

    // field windows
    assign header_ipv4_valid = header_byte_active && !output_abort;
    assign total_length_valid = header_ipv4_valid && (read == HEADER)
                              && ((header_count == 5'd2)
                               || (header_count == 5'd3)); // bytes 2-3
    assign protocol_valid = header_ipv4_valid && (read == HEADER)
                          && (header_count == 5'd9);       // byte 9
    assign source_ip_valid = header_ipv4_valid && (read == HEADER)
                           && (header_count >= 5'd12)
                           && (header_count <= 5'd15);     // bytes 12-15
    assign destination_ip_valid = header_ipv4_valid && (read == HEADER)
                                && (header_count >= 5'd16)
                                && (header_count <= 5'd19); // bytes 16-19
    assign payload_ipv4_valid = (read == PAYLOAD) && data_valid
                              && (bytes_remaining != 0) && !output_abort;

    assign end_of_payload = !output_abort
                          && ((payload_ipv4_valid && (bytes_remaining == 1))
                           || ((read == HEADER) && data_valid
                            && (header_count == 5'd19)
                            && (bytes_remaining == 0)));

    // parsing process
    always_ff @(posedge clk) begin
        if (rst) begin
            read            <= IDLE;
            header_count    <= '0;
            length_high     <= '0;
            bytes_remaining <= '0;
            checksum_sum    <= '0;
            err_latch       <= 1'b0;
        end else begin
            case (read)
                IDLE: begin
                    header_count    <= '0;
                    length_high     <= '0;
                    bytes_remaining <= '0;
                    checksum_sum    <= '0;
                    err_latch       <= 1'b0;

                    if (data_start && data_valid) begin
                        header_count <= 5'd1;
                        checksum_sum <= checksum_add_byte(16'b0, data, 1'b1);

                        if (version_ihl_error_now || data_error) begin
                            read      <= DROP;
                            err_latch <= 1'b1;
                        end else begin
                            read <= HEADER;
                        end
                    end else begin
                        read <= IDLE;
                    end
                end

                HEADER: begin
                    if (data_valid) begin
                        checksum_sum <= checksum_next;

                        if (header_count == 5'd2) begin
                            length_high <= data;
                        end

                        if ((header_count == 5'd3) && !length_error_now) begin
                            bytes_remaining <= length_candidate - 16'd20;
                        end

                        if (length_error_now || fragment_error_now
                            || checksum_error_now) begin
                            read      <= DROP;
                            err_latch <= 1'b1;
                        end else if (header_count == 5'd19) begin
                            if (bytes_remaining == 0) begin
                                read <= WAIT_END;
                            end else begin
                                read <= PAYLOAD;
                            end
                        end else begin
                            header_count <= header_count + 1'b1;
                        end
                    end
                end

                PAYLOAD: begin
                    if (data_valid) begin
                        if (bytes_remaining > 1) begin
                            bytes_remaining <= bytes_remaining - 1'b1;
                        end else begin
                            bytes_remaining <= '0;
                            read            <= WAIT_END;
                        end
                    end
                end

                WAIT_END: begin
                    // ignore ethernet padding after ipv4 payload
                    read <= WAIT_END;
                end

                DROP: begin
                    // hold error through the packet boundary
                    read <= DROP;
                end

                default: begin
                    read      <= IDLE;
                    err_latch <= 1'b1;
                end
            endcase

            // pass a stream error to drop the packet
            if ((read != IDLE) && data_error) begin
                read      <= DROP;
                err_latch <= 1'b1;
            end

            // remember a short packet through its final boundary
            if (truncation_error_now) begin
                err_latch <= 1'b1;
            end

            // packet boundary has final priority
            if (data_end && packet_context) begin
                read            <= IDLE;
                header_count    <= '0;
                length_high     <= '0;
                bytes_remaining <= '0;
                checksum_sum    <= '0;
            end
        end
    end

endmodule
