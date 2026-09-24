package gmii_pkg;
    import uvm_pkg::*;
    `include "uvm_macros.svh"
    import tb_utils_pkg::*;

    // one ethernet frame as it goes on the wire, no preamble
    class eth_frame_item extends uvm_sequence_item;
        `uvm_object_utils(eth_frame_item)

        rand bit [47:0] dst;
        rand bit [47:0] src;
        rand bit [15:0] ethertype;
        rand int unsigned payload_len;
        rand byte unsigned payload[];

        // error knobs, -1 means off
        rand bit corrupt_fcs;
        rand int rx_er_at;
        rand int truncate_at;

        // idle cycles after the frame
        rand int unsigned gap;

        // xsim wants the size set from a plain variable
        constraint c_payload {
            soft payload_len inside {[46:1500]};
            payload.size() == payload_len;
        }
        constraint c_errors {
            soft corrupt_fcs == 0;
            soft rx_er_at == -1;
            soft truncate_at == -1;
        }
        constraint c_gap { gap inside {[12:20]}; }

        function new(string name = "eth_frame_item");
            super.new(name);
        endfunction

        // header, payload, and fcs in wire order
        function bytes_t frame_bytes();
            bytes_t b;
            for (int i = 5; i >= 0; i--) b.push_back(dst[8*i +: 8]);
            for (int i = 5; i >= 0; i--) b.push_back(src[8*i +: 8]);
            b.push_back(ethertype[15:8]);
            b.push_back(ethertype[7:0]);
            foreach (payload[i]) b.push_back(payload[i]);
            append_fcs(b);
            if (corrupt_fcs) b[b.size()-1] ^= 8'h5A;
            return b;
        endfunction

        function string convert2string();
            return $sformatf("type %04h payload %0d fcs_bad %0b rx_er_at %0d truncate_at %0d",
                             ethertype, payload.size(), corrupt_fcs, rx_er_at, truncate_at);
        endfunction
    endclass

endpackage
