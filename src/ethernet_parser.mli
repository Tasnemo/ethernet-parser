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
    ; header_valid : 'a
    ; payload_data : 'a
    ; payload_valid : 'a
    ; payload_last : 'a
    ; malformed : 'a
    }
  [@@deriving hardcaml]
end

val create : Scope.t -> Signal.t I.t -> Signal.t O.t
val hierarchical : Scope.t -> Signal.t I.t -> Signal.t O.t
