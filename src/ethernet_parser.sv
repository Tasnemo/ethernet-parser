module ethernet_parser (
    // purely data link layer

    input logic rx_clk,
    input logic rst,
    // GMII PHY input interface
    input logic[7:0] rxd,
    input logic rx_dv,
    input logic rx_er,

    // output stream
    output logic [7:0] o_stream,

    //stage valid signals
    output logic payload_ether_valid,
    output logic ethertype_valid,

    // progress checking
    output logic end_of_packet,
    output logic start_of_packet,

    // error output
    output logic ether_error

  );
  // general standards
    localparam int MAX_PAYLOAD = 1500;
    localparam int MIN_PAYLOAD = 46;
    localparam int FCS_BYTES   = 4;
    localparam int MAX_COUNT   = MAX_PAYLOAD + FCS_BYTES; // 1504
    localparam int MIN_COUNT   = MIN_PAYLOAD + FCS_BYTES; // 50

  typedef enum logic[2:0] {IDLE, DEST_MAC, SOUR_MAC, ETHER_TYPE,
                           PAYLOAD, FCS, DROP} protocol_stages;
  protocol_stages read;
    logic[10:0] byte_count; // 0 - 1504
    logic[3:0] counter;
    logic err_latch;

    //delay signals to filter out FCS on output
    logic[31:0] shift_reg;
    assign o_stream = shift_reg[31:24];

    // head of pipe decodes - these describe the byte on rxd this cycle
    logic hd_sop, hd_ethertype, hd_payload;
    assign hd_sop       = (read == IDLE) && rx_dv;    // byte 0
    assign hd_ethertype = (read == ETHER_TYPE);       // bytes 12-13
    // the length cap rides the delay line with the data, so the suppression
    // lands already aligned at the output
    assign hd_payload   = (read == PAYLOAD) && rx_dv && (byte_count < MAX_PAYLOAD);

    // each decode delayed 4 to line up with o_stream
    logic [3:0] sop_shift;
    logic [3:0] et_shift;
    logic [3:0] valid_shift;
    logic       rx_dv_d;

    // packet framing signals
    assign start_of_packet     = sop_shift[3];
    assign ethertype_valid     = et_shift[3]    && rx_dv;
    assign payload_ether_valid = valid_shift[3] && rx_dv;
    // frame complete pulse, lands one cycle after the last payload byte
    assign end_of_packet       = rx_dv_d && !rx_dv;

    // size check and combinatorial for fast catching
    assign ether_error = err_latch || (end_of_packet && (byte_count < MIN_COUNT));

    // 4 clock delay processs
    always_ff @(posedge rx_clk) begin
        if (rst) begin
            sop_shift   <= '0;
            et_shift    <= '0;
            valid_shift <= '0;
            rx_dv_d     <= 0;
        end else begin
            sop_shift   <= {sop_shift[2:0],   hd_sop};
            et_shift    <= {et_shift[2:0],    hd_ethertype};
            valid_shift <= {valid_shift[2:0], hd_payload};
            rx_dv_d     <= rx_dv;
        end
    end


// parsing process
  always_ff @(posedge rx_clk)
  begin
    if(rst)
    begin
      read <= IDLE;
      //general startup defaults
      byte_count <= 0;
      counter <= 0;
      err_latch <= 0;
      shift_reg <= '0;
    end
    else begin
        case (read)
        IDLE:
        begin
        byte_count <= 0;
        counter <= 0;
        err_latch <= 0;
        shift_reg <= '0;
        if (rx_dv)
            begin
                read <= DEST_MAC;
                // preemptive shift on state transition
                shift_reg <= {24'b0, rxd};
                counter <= 1;
            end
        end

        DEST_MAC:
        begin
            shift_reg <= {shift_reg[23:0],rxd};
            counter <= counter + 1;
            if(counter == 5) begin
                read <= SOUR_MAC;
            end
            if (!rx_dv) begin
                read <= IDLE; // truncated mid header
            end
        end

        SOUR_MAC:
        begin
            shift_reg <= {shift_reg[23:0],rxd};
            counter <= counter + 1;
            if(counter == 11) begin
                read <= ETHER_TYPE;

            end
            if (!rx_dv) begin
                read <= IDLE; // truncated mid header
            end
        end

        ETHER_TYPE:
        begin
            shift_reg <= {shift_reg[23:0], rxd};
            counter <= counter + 1;
            if (counter == 13) begin
                read <= PAYLOAD;
            end
            if (!rx_dv) begin
                read <= IDLE; // truncated mid header
            end
        end

        PAYLOAD:
        begin
            shift_reg <= {shift_reg[23:0], rxd};
            
            if (rx_dv) begin
                byte_count <= byte_count + 1;
                if (byte_count >= MAX_COUNT) begin
                    read      <= DROP;
                    err_latch <= 1;
                end
            end else begin
                read <= IDLE;
            end
        end

        DROP:
        begin
            // over length so drop 
            if (!rx_dv) begin
                read <= IDLE;
            end
        end

        default: read <= IDLE;
        endcase

        end

    end




endmodule
