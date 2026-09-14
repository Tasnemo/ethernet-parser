module ethernet_parser (
    // purely data link layer

    input logic rx_clk,
    input logic rst,
    // GMII PHY input interface
    input logic[7:0] rxd,
    input logic rx_dv,
    input logic rx_er,

    //downstream payload send
    output logic payload_ether[7:0],
    output logic payload_ether_valid
    // ethertype send for routing
    output logic[7:0] ethertype,
    output logic ethertype_valid

    // progress checking
    output logic eof,
    output logic sof,

    // error output
    output logic ether_error
  );
  typedef enum logic[2:0] {IDLE, DEST_MAC, SOUR_MAC. ETHER_TYPE,
                           PAYLOAD, FCS} protocol_stages
          protocol_stages read;
  logic[10:0] byte_count; // 0 - 1526
  logic[31:0]  4_byte_shift;

  assign payload_ether =  4_byte_shift[31:24];


  always_ff @(posedge clk)
  begin
    if(rst)
    beginis it fine 
      read <= IDLE;
      //general startup defaults
      payload_ether <= '0;
      payload_ether_valid <= 0;
      ethertype <= '0;
      ethertype_valid <= 0;
      eof <= 0;
      sof <= 0; 
      byte_count <= 0;
      4_byte_shift <= '0;
    end
    else if (rx_clk) begin
        case (read)
        IDLE:
        begin
        payload_ether <= 0;
        payload_ether_valid <= 0;
        ethertype <= '0;
        ethertype_valid <= 0;
        eof <= 0;
        sof <= 0; 
        byte_count <= 0;
        4_byte_shift <= '0;
        if (rx_dv)
            begin
                read <= DEST_MAC;
                4_byte_shift <= {4_byte_shift[23:0],rxd};
                counter <= counter + 1;
            end
        end

        DEST_MAC:
        begin
            4_byte_shift <= {4_byte_shift[23:0],rxd};
            counter <= counter + 1;
            if(counter == 6) begin
                read <= SOUR_MAC;
            end
        end

        SOUR_MAC:
        begin
            4_byte_shift <= {4_byte_shift[23:0],rxd};
            counter <= counter + 1;
            if(counter == 13) begin
                read <= SOUR_MAC;
                
            end
            
        end
        PAYLOAD:
        begin 
            4_byte_shift
        end 
        endcase

        end

    end
endmodule
