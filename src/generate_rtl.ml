open! Core
open! Hardcaml

module Top = Packet_engine_top

let generate () =
  let module C = Circuit.With_interface (Top.I) (Top.O) in
  let scope = Scope.create ~auto_label_hierarchical_ports:true () in
  let circuit = C.create_exn ~name:"packet_engine_top" (Top.hierarchical scope) in
  let rtl = Rtl.create Verilog [ circuit ] in
  Stdio.print_endline (Rtl.to_string rtl)
;;

let () = generate ()
