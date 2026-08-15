# hardcaml-packet-engine

This repository is an extremely Hardcaml + Cocotb packet parser scaffold. 

## Milestones

1. The first milestone is an Ethernet parser that captures the 14-byte Ethernet header, forwards payload bytes, and exposes header validity and malformed status.
2. Then would be to add IPv4 parsing so the design can pull out the main header fields, check the basic packet structure, and pass the payload into the next stage.
3. After that, add UDP parsing for the source and destination ports, packet length, and payload so the full Ethernet to IPv4 to UDP path works end to end.

## Current scope

- Hardcaml source modules live under src/
- Cocotb-oriented scaffolding and Python test helpers live under test/
- Generated RTL is expected under rtl/

## Test usage

The current Python-level test scaffold can be exercised with:

```bash
./.venv/bin/python.exe -m pytest -q test
```

## Limitations

- One byte per clock cycle
- No backpressure or ready signal
- Only one packet in flight at a time
- IPv4 parsing is intentionally minimal in this initial scaffold
