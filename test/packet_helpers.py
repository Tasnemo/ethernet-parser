from __future__ import annotations

import random
import socket
import struct
from typing import Iterable


def build_ethernet_frame(destination_mac: bytes, source_mac: bytes, ethertype: int, payload: bytes) -> bytes:
    assert len(destination_mac) == 6
    assert len(source_mac) == 6
    return destination_mac + source_mac + struct.pack(">H", ethertype) + payload


def build_ipv4_packet(source_ip: str, destination_ip: str, protocol: int, payload: bytes) -> bytes:
    src = socket.inet_aton(source_ip)
    dst = socket.inet_aton(destination_ip)
    version_ihl = 0x45
    total_length = 20 + len(payload)
    header = struct.pack(">BBHHHBBH4s4s", version_ihl, 0, total_length, 0, 0, 64, protocol, 0, src, dst)
    return header + payload


def build_udp_segment(source_port: int, destination_port: int, payload: bytes) -> bytes:
    return struct.pack(">HHHH", source_port, destination_port, 8 + len(payload), 0) + payload


async def send_byte_stream(dut, data: bytes, valid_gap_probability: float = 0.0) -> None:
    for index, byte in enumerate(data):
        if valid_gap_probability and random.random() < valid_gap_probability:
            dut.input_valid.value = 0
            await dut._clk_edge()
        dut.input_data.value = byte
        dut.input_valid.value = 1
        dut.input_start.value = 1 if index == 0 else 0
        dut.input_last.value = 1 if index == len(data) - 1 else 0
        await dut._clk_edge()
    dut.input_valid.value = 0
    dut.input_start.value = 0
    dut.input_last.value = 0
    await dut._clk_edge()
