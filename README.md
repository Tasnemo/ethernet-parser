# hardcaml-packet-engine

This repository is a beginner-friendly Hardcaml + Cocotb packet parser scaffold. The first milestone is an Ethernet parser that captures the 14-byte Ethernet header, forwards payload bytes, and exposes header validity and malformed status.

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
