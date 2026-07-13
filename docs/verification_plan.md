# Verification Plan

The verification plan uses Cocotb to drive the generated Verilog and check parser behavior for:

- valid IPv4/UDP packets
- ARP and IPv6 Ethernet frames
- malformed and truncated headers
- gaps in the input byte stream
- reset during packet capture
