module ipv4_parser (
    parameter int MAX_IPV4_BYTES = 1500
) (
    input logic clk,
    input logic rst,

    input logic [7:0] data,
    input logic data_valid,
    input logic data_start,
    input logic data_end,
    input logic data_error,
    output logic [7:0] o_stream,

    output logic header_ipv4_valid,
    output logic total_length_valid,
    output logic protocol_valid,
    output logic source_ip_valid,
    output logic destination_ip_valid,
    output logic payload_ipv4_valid,

    output logic start_of_packet,
    output logic end_of_payload,
    output logic end_of_packet,

    output logic header_checksum_error,
    output logic ipv4_error
);

    typedef enum logic [2:0] {
        IDLE,
        HEADER,
        PAYLOAD,
        WAIT_END,
        DROP
    } protocol_stage_t;

    protocol_stage_t read;
    logic [4:0] header_count;
    logic first_header_byte;
    logic header_byte_active;
    logic packet_context;

    assign first_header_byte = (read == IDLE) && data_start && data_valid;
    assign header_byte_active = first_header_byte
                              || ((read == HEADER) && data_valid);
    assign packet_context = (read != IDLE) || first_header_byte;

    assign o_stream = data;
    assign header_ipv4_valid = header_byte_active;
    assign total_length_valid = 1'b0;
    assign protocol_valid = 1'b0;
    assign source_ip_valid = 1'b0;
    assign destination_ip_valid = 1'b0;
    assign payload_ipv4_valid = (read == PAYLOAD) && data_valid;

    assign start_of_packet = first_header_byte;
    assign end_of_payload = 1'b0;
    assign end_of_packet = data_end && packet_context;

    assign header_checksum_error = 1'b0;
    assign ipv4_error = 1'b0;

    always_ff @(posedge clk) begin
        if (rst) begin
            read <= IDLE;
            header_count <= 5'd0;
        end else if (data_end) begin
            read <= IDLE;
            header_count <= 5'd0;
        end else begin
            case (read)
                IDLE: begin
                    header_count <= 5'd0;
                    if (data_start && data_valid) begin
                        read <= HEADER;
                        header_count <= 5'd1;
                    end
                end

                HEADER: begin
                    if (data_valid) begin
                        if (header_count == 5'd19) begin
                            read <= PAYLOAD;
                        end else begin
                            header_count <= header_count + 5'd1;
                        end
                    end
                end

                PAYLOAD: begin
                    read <= PAYLOAD;
                end

                WAIT_END: begin
                    read <= WAIT_END;
                end

                DROP: begin
                    read <= DROP;
                end

                default: begin
                    read <= IDLE;
                    header_count <= 5'd0;
                end
            endcase
        end
    end

endmodule
