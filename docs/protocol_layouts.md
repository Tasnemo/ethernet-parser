# Protocol Layouts

The initial scaffold documents the Ethernet header layout and the basic IPv4/UDP assumptions that are expected for the first implementation.

- Ethernet: 14-byte header followed by payload bytes.
- IPv4: fixed 20-byte header with no options.
- UDP: header immediately follows the IPv4 payload section.
