from pathlib import Path
import sys
from types import SimpleNamespace

sys.path.append(str(Path(__file__).resolve().parent))

from packet_helpers import build_ethernet_frame, send_byte_stream


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


def test_send_byte_stream_sets_start_and_last_bits() -> None:
    class DummyDut:
        def __init__(self) -> None:
            self.input_data = SimpleNamespace(value=0)
            self.input_valid = SimpleNamespace(value=0)
            self.input_start = SimpleNamespace(value=0)
            self.input_last = SimpleNamespace(value=0)
            self.events = []

        async def _clk_edge(self) -> None:
            self.events.append((self.input_start.value, self.input_last.value))

    import asyncio

    dut = DummyDut()
    asyncio.run(send_byte_stream(dut, b"ab"))

    assert dut.events[0][0] == 1
    assert dut.events[0][1] == 0
    assert dut.events[1][0] == 0
    assert dut.events[1][1] == 1
