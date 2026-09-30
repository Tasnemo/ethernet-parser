# ethernet-parser

byte per clock ethernet -> ipv4 -> udp packet parser in systemverilog, verified with uvm on vivado xsim.

started out prototyping the whole thing in hardcaml + cocotb (thats still on the `Hardcaml-+-cocotb` branch) to figure out the protocols and policies, then moved it over to plain SV once the design settled. the SV version is what this branch is about now

## whats in here

```
src/
  ethernet_parser.sv            gmii in, strips header + fcs, checks crc32 / runts / oversize
  ipv4_parser.sv                ihl 5 only, length + checksum checks, rejects fragments
  udp_parser.sv                 pseudo header checksum, port 0 reject, zero checksum = skip
  ether_ipv4_udp_top_level.sv   full_parser, routes 0x0800 -> ipv4 and proto 17 -> udp
tb/
  common/        crc + checksum helpers, generic scoreboard
  agents/gmii/   gmii driver/monitor for ethernet + top
  agents/stream/ byte stream driver/monitor for ipv4 + udp
  env/<bench>/   one uvm env per block + one for the top
sim/
  sim.tcl        build a vivado project and run one test
  regress.tcl    run every test on every bench over a few seeds
docs/            protocol layouts and architecture notes
```

## the parsers

everything streams one byte a clock, no backpressure, one packet in flight at a time.

- **ethernet**: takes gmii (rxd / rx_dv / rx_er) with no preamble. payload comes out 4 cycles late so the fcs gets dropped for free. errors on bad fcs, runts (<46 payload), over 1500, or rx_er
- **ipv4**: version 4 / ihl 5 only (no options). checks total length, header checksum, and rejects mf / offset / reserved bit (df is fine, no reassembly here). anything past total length is treated as ethernet padding
- **udp**: length has to line up with where ipv4 says the payload ends. checksum covers the pseudo header, a zero checksum means the sender skipped it
- **top**: `full_parser` spits out the udp payload on `parser` with `parser_valid`, `parser_start`, `parser_last`, `parser_error`

outputs are speculative, bytes can come out before an error shows up (checksum verdict lands on the last byte), so whatever consumes this should wait for `parser_last` / `parser_error` before trusting a packet.

the ipv4 and udp fsms got squished for area (state + header index fused into one cursor), ipv4 went from 44 to 32 flops doing that.

## running sims

needs vivado (built on 2025.2), uvm 1.2 comes with xsim so nothing else to install.

```
vivado -mode batch -notrace -source sim/sim.tcl -tclargs ethernet eth_smoke_test
vivado -mode batch -notrace -source sim/sim.tcl -tclargs top top_mixed_test 7
vivado -mode batch -notrace -source sim/regress.tcl              # everything, seeds 1 2 3
vivado -mode batch -notrace -source sim/regress.tcl -tclargs udp 1 2 3 4 5
```

for waves open vivado and in the tcl console do `set argv {top top_mixed_test}; source sim/sim.tcl`

benches are `ethernet`, `ipv4`, `udp`, `top`. each one has smoke / error / random tests plus a couple extra (boundary + back to back for ethernet, stalls + stream errors for ipv4 and udp, directed cases for top). every bench has a ref model + scoreboard + coverage, the top one just chains the three block ref models together.

full regression is 19 tests x 3 seeds, all passing, takes ~15-20 min.

## limitations / notes

- no ipv4 options, no fragments, no vlan tags, no ipv6 (just gets ignored)
- max 1500 byte ipv4 packet, 1480 byte udp
- ethernet parser needs at least 4 idle cycles between frames or stale bytes leak into the next payload. 802.3 wants 12 anyway so its fine but its there
- no preamble / sfd handling, frames start at the dest mac

## todo

- tinytapeout / openlane area numbers (only have vivado xc7a35t numbers so far)
- vlan tag support maybe
