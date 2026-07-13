from pathlib import Path
import sys

sys.path.append(str(Path(__file__).resolve().parent))

from packet_helpers import build_ethernet_frame


def test_build_ethernet_frame_preserves_header_and_payload() -> None:
    destination_mac = b"\x02\x00\x00\x00\x00\x01"
    source_mac = b"\x02\x00\x00\x00\x00\x02"
    payload = b"hello"

    frame = build_ethernet_frame(destination_mac, source_mac, 0x0800, payload)

    assert len(frame) == 14 + len(payload)
    assert frame[:6] == destination_mac
    assert frame[6:12] == source_mac
    assert frame[12:14] == b"\x08\x00"
    assert frame[14:] == payload
