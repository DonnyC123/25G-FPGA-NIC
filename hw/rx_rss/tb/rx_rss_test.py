import random

import cocotb
from scapy.layers.inet import IP, TCP, UDP
from scapy.layers.inet6 import IPv6
from scapy.layers.l2 import Ether
from scapy.packet import Packet

from hw.common.pkg import rss_pkg as pkg
from hw.rx_parser.tb.parser_frames import KNOWN_FRAMES, valid_frame
from hw.rx_rss.tb.rss_model import DEFAULT_KEY, MS_VECTORS, toeplitz, vector_input
from hw.rx_rss.tb.rx_rss_test_base import RxRssTestBase
from hw.tb_utils.net.packets import add_fcs, pad


def stream(data: bytes) -> bytes:
    return add_fcs(pad(data))


def vector_frame(src: str, dst: str, l4: Packet) -> bytes:
    l3 = IPv6(src=src, dst=dst) if ":" in src else IP(src=src, dst=dst)
    eth = Ether(src="02:00:00:00:00:01", dst="02:00:00:00:00:02")
    return stream(bytes(eth / l3 / l4))


def random_reta() -> list[int]:
    return [random.randrange(pkg.RSS_MAX_QUEUES) for _ in range(pkg.RETA_SIZE)]


@cocotb.test()
async def test_model_matches_microsoft_vectors(dut) -> None:
    for src, sport, dst, dport, l3_hash, l4_hash in MS_VECTORS:
        assert toeplitz(vector_input(src, dst), DEFAULT_KEY) == l3_hash
        assert toeplitz(vector_input(src, dst, sport, dport), DEFAULT_KEY) == l4_hash
    tb = await RxRssTestBase.start(dut)
    await tb.finish()


@cocotb.test()
async def test_microsoft_vectors(dut) -> None:
    tb = await RxRssTestBase.start(dut)
    seq = tb.sequence
    for src, sport, dst, dport, _, _ in MS_VECTORS:
        await seq.add_frame(vector_frame(src, dst, TCP(sport=sport, dport=dport)))
        await seq.add_frame(vector_frame(src, dst, UDP(sport=sport, dport=dport)))
        await seq.add_idle(2)
    await tb.finish()


@cocotb.test()
async def test_microsoft_vectors_udp_ports(dut) -> None:
    tb = await RxRssTestBase.start(dut, udp_ports_en=True)
    seq = tb.sequence
    for src, sport, dst, dport, _, _ in MS_VECTORS:
        await seq.add_frame(vector_frame(src, dst, UDP(sport=sport, dport=dport)))
        await seq.add_idle(2)
    await tb.finish()


@cocotb.test()
async def test_known_frames(dut) -> None:
    tb = await RxRssTestBase.start(dut, udp_ports_en=True)
    seq = tb.sequence
    for packet in KNOWN_FRAMES:
        await seq.add_frame(stream(bytes(packet)))
        await seq.add_idle(2)
    await tb.finish()


@cocotb.test()
async def test_random_key_and_reta(dut) -> None:
    tb = await RxRssTestBase.start(
        dut,
        key=random.randbytes(pkg.RSS_KEY_BYTES),
        udp_ports_en=random.random() < 0.5,
        reta=random_reta(),
    )
    seq = tb.sequence
    seq.bubble_rate = 0.1
    for _ in range(300):
        await seq.add_frame(stream(valid_frame()))
        await seq.add_idle(random.choice([0, 0, 1, 3]))
    await tb.finish()


@cocotb.test()
async def test_reta_reprogram(dut) -> None:
    tb = await RxRssTestBase.start(dut)
    seq = tb.sequence
    for _ in range(3):
        for _ in range(50):
            await seq.add_frame(stream(valid_frame()))
        await tb.program_reta(random_reta())
    await tb.finish()
