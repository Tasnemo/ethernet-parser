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
    ; header_valid : 'a
    ; payload_data : 'a [@bits 8]
    ; payload_valid : 'a
    ; payload_last : 'a
    ; malformed : 'a
    }
  [@@deriving hardcaml]
end

module States = struct
  type t =
    | Idle
    | Header
    | Payload
  [@@deriving sexp_of, compare ~localize, enumerate]
end

let create _scope ({ clock; reset; input_data; input_valid; input_start; input_last } : _ I.t) : _ O.t =
  let spec = Reg_spec.create ~clock ~clear:reset () in
  let open Always in
  let sm = State_machine.create (module States) spec in
  let byte_count = Variable.reg spec ~width:4 in
  let destination_mac = Variable.reg spec ~width:48 in
  let source_mac = Variable.reg spec ~width:48 in
  let ethertype = Variable.reg spec ~width:16 in
  let header_valid = Variable.reg spec ~width:1 in
  let malformed = Variable.reg spec ~width:1 in
  let payload_valid = Variable.reg spec ~width:1 in
  let payload_last = Variable.reg spec ~width:1 in
  let payload_data = Variable.reg spec ~width:8 in

  compile
    [ sm.switch
        [ ( Idle
          , [ when_
                input_start
                [ byte_count <--. 0
                ; header_valid <--. 0
                ; malformed <--. 0
                ; sm.set_next Header
                ]
            ] )
        ; ( Header
          , [ when_
                input_valid
                [ byte_count <-- byte_count.value +:. 1
                ; when_ (byte_count.value ==:. 0) [ destination_mac <-- (zero 40) @: input_data ]
                ; when_ (byte_count.value ==:. 1) [ destination_mac <-- (destination_mac.value[47:8]) @: input_data ]
                ; when_ (byte_count.value ==:. 2) [ destination_mac <-- (destination_mac.value[47:8]) @: input_data ]
                ; when_ (byte_count.value ==:. 3) [ destination_mac <-- (destination_mac.value[47:8]) @: input_data ]
                ; when_ (byte_count.value ==:. 4) [ destination_mac <-- (destination_mac.value[47:8]) @: input_data ]
                ; when_ (byte_count.value ==:. 5) [ destination_mac <-- (destination_mac.value[47:8]) @: input_data ]
                ; when_ (byte_count.value ==:. 6) [ source_mac <-- (zero 40) @: input_data ]
                ; when_ (byte_count.value ==:. 7) [ source_mac <-- (source_mac.value[47:8]) @: input_data ]
                ; when_ (byte_count.value ==:. 8) [ source_mac <-- (source_mac.value[47:8]) @: input_data ]
                ; when_ (byte_count.value ==:. 9) [ source_mac <-- (source_mac.value[47:8]) @: input_data ]
                ; when_ (byte_count.value ==:. 10) [ source_mac <-- (source_mac.value[47:8]) @: input_data ]
                ; when_ (byte_count.value ==:. 11) [ source_mac <-- (source_mac.value[47:8]) @: input_data ]
                ; when_ (byte_count.value ==:. 12) [ ethertype <-- (zero 8) @: input_data ]
                ; when_ (byte_count.value ==:. 13) [ ethertype <-- ethertype.value[15:8] @: input_data ]
                ; when_ (byte_count.value ==:. 13) [ header_valid <--. 1 ]
                ; when_ (byte_count.value ==:. 13) [ sm.set_next Payload ]
                ; when_ input_last [ malformed <--. 1; sm.set_next Idle ]
                ]
            ] )
        ; ( Payload
          , [ when_
                input_valid
                [ payload_data <-- input_data
                ; payload_valid <--. 1
                ; payload_last <-- input_last
                ; when_ input_last [ sm.set_next Idle ]
                ]
            ] )
        ]
    ];

  { destination_mac = destination_mac.value
  ; source_mac = source_mac.value
  ; ethertype = ethertype.value
  ; header_valid = header_valid.value
  ; payload_data = payload_data.value
  ; payload_valid = payload_valid.value
  ; payload_last = payload_last.value
  ; malformed = malformed.value
  }
;;

let hierarchical scope =
  let module Scoped = Hierarchy.In_scope (I) (O) in
  Scoped.hierarchical ~scope ~name:"ethernet_parser" create
;;
