# Architecture

The first milestone focuses on a single-byte streaming parser pipeline:

1. An Ethernet parser captures the 14-byte header and forwards the payload stream.
2. An IPv4/UDP parser consumes the Ethernet payload and reports parsed metadata.
3. A top-level packet engine instantiates both blocks and exposes their outputs in one interface.
