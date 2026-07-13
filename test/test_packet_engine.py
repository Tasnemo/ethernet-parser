from pathlib import Path


def test_repository_layout_contains_expected_sources() -> None:
    root = Path(__file__).resolve().parents[1]
    required_files = [
        root / "src" / "ethernet_parser.ml",
        root / "src" / "ipv4_udp_parser.ml",
        root / "src" / "packet_engine_top.ml",
        root / "test" / "packet_helpers.py",
    ]

    for path in required_files:
        assert path.exists(), f"expected {path} to exist"
