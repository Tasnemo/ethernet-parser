from pathlib import Path
import socket
import struct
import sys

sys.path.append(str(Path(__file__).resolve().parent))

from packet_helpers import build_ipv4_packet, build_udp_segment


def test_ipv4_packet_helpers_pack_expected_fields() -> None:
    payload = b"hello"
    packet = build_ipv4_packet("192.168.1.10", "192.168.1.20", 17, payload)

    version_ihl = packet[0]
    total_length = struct.unpack(">H", packet[2:4])[0]
    protocol = packet[9]
    source_ip = socket.inet_ntoa(packet[12:16])
    destination_ip = socket.inet_ntoa(packet[16:20])

    assert version_ihl >> 4 == 4
    assert (version_ihl & 0x0F) == 5
    assert total_length == 20 + len(payload)
    assert protocol == 17
    assert source_ip == "192.168.1.10"
    assert destination_ip == "192.168.1.20"


def test_udp_segment_helper_builds_udp_header() -> None:
    segment = build_udp_segment(40000, 5000, b"hello")

    source_port, destination_port, udp_length, _checksum = struct.unpack(">HHHH", segment[:8])

    assert source_port == 40000
    assert destination_port == 5000
    assert udp_length == 8 + 5
    assert segment[8:] == b"hello"
