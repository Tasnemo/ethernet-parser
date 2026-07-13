open! Core
open! Hardcaml
open! Hardcaml.Signal

module I = struct
  type 'a t =
    { clock : 'a
    ; reset : 'a
    ; input_data : 'a [@bits 8]
    ; input_valid : 'a
    ; input_start : 'a
    ; input_last : 'a
    }
  [@@deriving hardcaml]
end

module O = struct
  type 'a t =
    { destination_mac : 'a [@bits 48]
    ; source_mac : 'a [@bits 48]
    ; ethertype : 'a [@bits 16]
    ; is_ipv4 : 'a
    ; is_udp : 'a
    ; source_ip : 'a [@bits 32]
    ; destination_ip : 'a [@bits 32]
    ; ip_protocol : 'a [@bits 8]
    ; source_port : 'a [@bits 16]
    ; destination_port : 'a [@bits 16]
    ; udp_length : 'a [@bits 16]
    ; packet_valid : 'a
    ; malformed : 'a
    }
  [@@deriving hardcaml]
end

let create scope ({ clock; reset; input_data; input_valid; input_start; input_last } : _ I.t) : _ O.t =
  let ethernet =
    Ethernet_parser.hierarchical scope
      { Ethernet_parser.I.clock
      ; reset
      ; input_data
      ; input_valid
      ; input_start
      ; input_last
      }
  in
  let ipv4 =
    Ipv4_udp_parser.hierarchical scope
      { Ipv4_udp_parser.I.payload_data = ethernet.payload_data
      ; payload_valid = ethernet.payload_valid
      ; payload_last = ethernet.payload_last
      ; ethertype = ethernet.ethertype
      ; ethernet_header_valid = ethernet.header_valid
      }
  in
  { O.destination_mac = ethernet.destination_mac
  ; source_mac = ethernet.source_mac
  ; ethertype = ethernet.ethertype
  ; is_ipv4 = ipv4.is_ipv4
  ; is_udp = ipv4.is_udp
  ; source_ip = ipv4.source_ip
  ; destination_ip = ipv4.destination_ip
  ; ip_protocol = ipv4.ip_protocol
  ; source_port = ipv4.source_port
  ; destination_port = ipv4.destination_port
  ; udp_length = ipv4.udp_length
  ; packet_valid = ipv4.packet_valid
  ; malformed = ethernet.malformed |: ipv4.malformed
  }
;;

let hierarchical scope =
  let module Scoped = Hierarchy.In_scope (I) (O) in
  Scoped.hierarchical ~scope ~name:"packet_engine_top" create
;;
