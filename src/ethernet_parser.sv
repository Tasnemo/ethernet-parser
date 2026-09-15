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
    output logic dest_mac_valid,
    output logic sour_mac_valid,
    output logic payload_ether_valid,
    output logic ethertype_valid,

    // progress checking
    output logic end_of_packet,
    output logic start_of_packet,

    // error output
    output logic fcs_error,
    output logic ether_error

  );
  // general standards
    localparam int MAX_PAYLOAD = 1500;
    localparam int MIN_PAYLOAD = 46;
    localparam int FCS_BYTES   = 4;
    localparam int MAX_COUNT   = MAX_PAYLOAD + FCS_BYTES; // 1504
    localparam int MIN_COUNT   = MIN_PAYLOAD + FCS_BYTES; // 50

  typedef enum logic[2:0] {IDLE, DEST_MAC, SOUR_MAC, ETHER_TYPE,
                           PAYLOAD, DROP} protocol_stages;
  protocol_stages read;
    logic[10:0] byte_count; // 0 - 1504
    logic[3:0] counter;
    logic err_latch;

    //delay signals to filter out FCS on output
    logic[31:0] shift_reg;
    assign o_stream = shift_reg[31:24];

    // header entities
    logic hd_sop, hd_dest_mac, hd_sour_mac, hd_ethertype, hd_payload;
    assign hd_sop       = (read == IDLE) && rx_dv;    // byte 0
    // some slicing due to data being collected during state transitions
    assign hd_dest_mac  = hd_sop || (read == DEST_MAC); // bytes 0-5
    assign hd_sour_mac  = (read == SOUR_MAC);          // bytes 6-11
    assign hd_ethertype = (read == ETHER_TYPE);        // bytes 12-13
    // the length cap rides the delay line with the data, so the suppression
    // lands already aligned at the output
    assign hd_payload   = (read == PAYLOAD) && rx_dv && (byte_count < MAX_PAYLOAD);

    // each decode delayed 4 to line up with o_stream
    logic [3:0] sop_shift;
    logic [3:0] dm_shift;
    logic [3:0] sm_shift;
    logic [3:0] et_shift;
    logic [3:0] valid_shift;
    logic       rx_dv_d;

    // packet framing signals
    assign start_of_packet     = sop_shift[3];
    assign dest_mac_valid      = dm_shift[3]    && rx_dv;
    assign sour_mac_valid      = sm_shift[3]    && rx_dv;
    assign ethertype_valid     = et_shift[3]    && rx_dv;
    assign payload_ether_valid = valid_shift[3] && rx_dv;
    // frame complete pulse, lands one cycle after the last payload byte
    assign end_of_packet       = rx_dv_d && !rx_dv;

    // size check and combinatorial for fast catching
    assign ether_error = err_latch
                      || (end_of_packet && (byte_count < MIN_COUNT))
                      || fcs_error;

    // 4 clock delay processs
    always_ff @(posedge rx_clk) begin
        if (rst) begin
            sop_shift   <= '0;
            dm_shift    <= '0;
            sm_shift    <= '0;
            et_shift    <= '0;
            valid_shift <= '0;
            rx_dv_d     <= 0;
        end else begin
            sop_shift   <= {sop_shift[2:0],   hd_sop};
            dm_shift    <= {dm_shift[2:0],    hd_dest_mac};
            sm_shift    <= {sm_shift[2:0],    hd_sour_mac};
            et_shift    <= {et_shift[2:0],    hd_ethertype};
            valid_shift <= {valid_shift[2:0], hd_payload};
            rx_dv_d     <= rx_dv;
        end
    end


// fcs constants
    localparam logic [31:0] CRC_POLY = 32'hEDB88320; // reversed ethernet polynomial
    localparam logic [31:0] CRC_SEED = 32'hFFFFFFFF; // seed and final xor

// one byte through the crc lsb first
    function automatic logic [31:0] crc32_byte(input logic [31:0] crc_in,
                                               input logic [7:0]  data);
        logic [31:0] c;
        // byte joins at the bottom
        c = crc_in ^ {24'b0, data};
        // walk a bit out and fold the polynomial back in on a 1
        for (int i = 0; i < 8; i++) begin
            if (c[0]) begin
                c = (c >> 1) ^ CRC_POLY;
            end
            else begin
                c = c >> 1;
            end
        end
        return c;
    endfunction

    logic [31:0] crc_reg;
    logic [31:0] fcs_received, fcs_computed;
    logic crc_en, frame_len_ok;

    // the tags are already every byte the crc covers so fcs drops out free
    assign crc_en = dest_mac_valid || sour_mac_valid
                 || ethertype_valid || payload_ether_valid;

// crc process
    always_ff @(posedge rx_clk) begin
        if (rst) begin
            crc_reg <= CRC_SEED;
        end
        // reseed on byte 0 because sop and the tags both fire on that cycle
        else if (start_of_packet) begin
            crc_reg <= crc32_byte(CRC_SEED, o_stream);
        end
        else if (crc_en) begin
            crc_reg <= crc32_byte(crc_reg, o_stream);
        end
    end

    // fcs still sits in the pipe oldest up top and arrives lsb first
    assign fcs_received = {shift_reg[7:0],   shift_reg[15:8],
                           shift_reg[23:16], shift_reg[31:24]};
    assign fcs_computed = crc_reg ^ CRC_SEED;

    // no usable fcs on a runt or an over length frame so skip the compare
    assign frame_len_ok = (read != DROP) && (byte_count >= MIN_COUNT);
    assign fcs_error    = end_of_packet && frame_len_ok
                       && (fcs_received != fcs_computed);


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

        // pass a PHY error or an internal error to throw out the packet
        if (rx_dv && rx_er) begin
            err_latch <= 1;
        end

        end

    end




endmodule
