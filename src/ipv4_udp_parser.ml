open! Core
open! Hardcaml
open! Hardcaml.Signal

module I = struct
  type 'a t =
    { payload_data : 'a [@bits 8]
    ; payload_valid : 'a
    ; payload_last : 'a
    ; ethertype : 'a [@bits 16]
    ; ethernet_header_valid : 'a
    }
  [@@deriving hardcaml]
end

module O = struct
  type 'a t =
    { is_ipv4 : 'a
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

let create _scope ({ payload_data; payload_valid; payload_last; ethertype; ethernet_header_valid } : _ I.t) : _ O.t =
  let open Signal in
  let is_ipv4 = ethernet_header_valid &: (ethertype ==:. 0x0800) in
  let is_udp = is_ipv4 &: payload_valid in
  let packet_valid = is_ipv4 &: payload_valid in
  let malformed = ethernet_header_valid &: (~: is_ipv4) in
  { is_ipv4
  ; is_udp
  ; source_ip = zero 32
  ; destination_ip = zero 32
  ; ip_protocol = zero 8
  ; source_port = zero 16
  ; destination_port = zero 16
  ; udp_length = zero 16
  ; packet_valid
  ; malformed
  }
;;

let hierarchical scope =
  let module Scoped = Hierarchy.In_scope (I) (O) in
  Scoped.hierarchical ~scope ~name:"ipv4_udp_parser" create
;;
