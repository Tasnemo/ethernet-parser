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

    // header entities
    logic packet_context;
    logic header_byte_active;

    // output stream
    assign o_stream = data;

    // header entities
    assign packet_context = (stage != IDLE) || (data_start && data_valid);
    assign header_byte_active = data_valid
                              && (((stage == IDLE) && data_start)
                               || (stage == HEADER));

    // packet framing signals
    assign start_of_packet = data_start && data_valid;
    assign end_of_packet = data_end && packet_context;

    // field windows
    // index is 0 in idle so byte 0 decodes the same way
    assign header_udp_valid = header_byte_active;                 // bytes 0-7
    assign source_port_valid = header_udp_valid
                             && (header_index[2:1] == 2'd0);      // bytes 0-1
    assign destination_port_valid = header_udp_valid
                                  && (header_index[2:1] == 2'd1); // bytes 2-3
    assign length_valid = header_udp_valid
                        && (header_index[2:1] == 2'd2);           // bytes 4-5
    assign checksum_valid = header_udp_valid
                          && (header_index[2:1] == 2'd3);         // bytes 6-7
    assign payload_udp_valid = (stage == PAYLOAD) && data_valid;

    // ipv4 marks the last segment byte
    assign end_of_payload = data_valid && data_last
                          && ((stage == PAYLOAD)
                           || ((stage == HEADER) && (header_index == 3'd7)));

    assign udp_checksum_error = 1'b0;
    assign udp_error = 1'b0;

// parsing process
    always_ff @(posedge clk) begin
        if (rst) begin
            stage        <= IDLE;
            header_index <= '0;
        end else begin
            case (stage)
                IDLE: begin
                    header_index <= '0;

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
                        if (header_index == 3'd7) begin
                            // byte 7 ends the header
                            if (data_last) begin
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
                    if (data_valid && data_last) begin
                        stage <= WAIT_END;
                    end
                end

                WAIT_END: begin
                    // wait for the frame boundary
                    stage <= WAIT_END;
                end

                DROP: begin
                    stage <= DROP;
                end

                default: stage <= IDLE;
            endcase

            // frame boundary reset
            if (data_end && packet_context) begin
                stage        <= IDLE;
                header_index <= '0;
            end
        end
    end

endmodule
