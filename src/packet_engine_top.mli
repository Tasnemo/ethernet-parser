open! Hardcaml

module I : sig
  type 'a t =
    { clock : 'a
    ; reset : 'a
    ; input_data : 'a
    ; input_valid : 'a
    ; input_start : 'a
    ; input_last : 'a
    }
  [@@deriving hardcaml]
end

module O : sig
  type 'a t =
    { destination_mac : 'a
    ; source_mac : 'a
    ; ethertype : 'a
    ; is_ipv4 : 'a
    ; is_udp : 'a
    ; source_ip : 'a
    ; destination_ip : 'a
    ; ip_protocol : 'a
    ; source_port : 'a
    ; destination_port : 'a
    ; udp_length : 'a
    ; packet_valid : 'a
    ; malformed : 'a
    }
  [@@deriving hardcaml]
end

val create : Scope.t -> Signal.t I.t -> Signal.t O.t
val hierarchical : Scope.t -> Signal.t I.t -> Signal.t O.t
