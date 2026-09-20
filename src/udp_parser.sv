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

    always_ff @(posedge clk) begin
        if (rst) begin
            stage <= IDLE;
        end else begin
            case (stage)
                IDLE,
                HEADER,
                PAYLOAD,
                WAIT_END,
                DROP: stage <= stage;
                default: stage <= IDLE;
            endcase
        end
    end

    always_comb begin
        o_stream = 8'h00;
        header_udp_valid = 1'b0;
        source_port_valid = 1'b0;
        destination_port_valid = 1'b0;
        length_valid = 1'b0;
        checksum_valid = 1'b0;
        payload_udp_valid = 1'b0;
        start_of_packet = 1'b0;
        end_of_payload = 1'b0;
        end_of_packet = 1'b0;
        udp_checksum_error = 1'b0;
        udp_error = 1'b0;
    end

endmodule
