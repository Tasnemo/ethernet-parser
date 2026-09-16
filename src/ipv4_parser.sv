module ipv4_parser_v01 #(
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

    always_ff @(posedge clk) begin
        if (rst) begin
            read <= IDLE;
        end else begin
            case (read)
                IDLE,
                HEADER,
                PAYLOAD,
                WAIT_END,
                DROP: read <= read;
                default: read <= IDLE;
            endcase
        end
    end

    always_comb begin
        o_stream = 8'h00;
        header_ipv4_valid = 1'b0;
        total_length_valid = 1'b0;
        protocol_valid = 1'b0;
        source_ip_valid = 1'b0;
        destination_ip_valid = 1'b0;
        payload_ipv4_valid = 1'b0;
        start_of_packet = 1'b0;
        end_of_payload = 1'b0;
        end_of_packet = 1'b0;
        header_checksum_error = 1'b0;
        ipv4_error = 1'b0;
    end

endmodule
