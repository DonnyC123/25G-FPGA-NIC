import random

import cocotb
from scapy.layers.inet import IP, TCP, UDP
from scapy.layers.inet6 import IPv6
from scapy.layers.l2 import Dot1AD, Dot1Q, Ether
from scapy.packet import Packet

from hw.rx_parser.tb.parser_frames import KNOWN_FRAMES, valid_frame
from hw.rx_parser.tb.rx_parser_test_base import RxParserTestBase
from hw.tb_utils.net.packets import add_fcs, pad
from hw.tb_utils.tx_eth_stream import WORD_BYTES


def stream(data: bytes) -> bytes:
    return add_fcs(pad(data))


def vlan_stack(depth: int) -> Packet:
    eth = Ether()
    for i in range(depth):
        eth = eth / (Dot1AD() if i == 0 and depth > 1 else Dot1Q())
    return eth


@cocotb.test()
async def test_known_frames(dut) -> None:
    tb = await RxParserTestBase.start(dut)
    seq = tb.sequence
    for packet in KNOWN_FRAMES:
        await seq.add_frame(stream(bytes(packet)))
        await seq.add_idle(2)
    await tb.finish()


@cocotb.test()
async def test_vlan_depths(dut) -> None:
    tb = await RxParserTestBase.start(dut)
    seq = tb.sequence
    for depth in range(4):
        for l3 in (IP(), IPv6()):
            tcp = TCP(sport=1000 + depth, dport=2000)
            udp = UDP(sport=3000, dport=4000 + depth)
            for l4 in (tcp, udp):
                await seq.add_frame(stream(bytes(vlan_stack(depth) / l3 / l4)))
                await seq.add_idle(2)
    await tb.finish()


@cocotb.test()
async def test_every_tail_length(dut) -> None:
    tb = await RxParserTestBase.start(dut)
    seq = tb.sequence
    for l3 in (IP(), IPv6()):
        base = bytes(Ether() / l3 / TCP(sport=1234, dport=5678))
        for extra in range(2 * WORD_BYTES):
            await seq.add_frame(stream(pad(base) + random.randbytes(extra)))
            await seq.add_idle(2)
    await tb.finish()


@cocotb.test()
async def test_back_to_back_frames(dut) -> None:
    tb = await RxParserTestBase.start(dut)
    seq = tb.sequence
    for _ in range(100):
        await seq.add_frame(stream(valid_frame()))
    await tb.finish()


@cocotb.test()
async def test_runt_after_frame(dut) -> None:
    tb = await RxParserTestBase.start(dut)
    seq = tb.sequence
    for _ in range(100):
        await seq.add_frame(stream(valid_frame()))
        await seq.add_frame(random.randbytes(random.randint(1, 12)))
    await tb.finish()


@cocotb.test()
async def test_bubbles(dut) -> None:
    tb = await RxParserTestBase.start(dut)
    seq = tb.sequence
    seq.bubble_rate = 0.3
    for _ in range(100):
        await seq.add_frame(stream(valid_frame()))
        await seq.add_idle(random.randint(0, 2))
    await tb.finish()


@cocotb.test()
async def test_random_traffic(dut) -> None:
    tb = await RxParserTestBase.start(dut)
    seq = tb.sequence
    seq.bubble_rate = 0.1
    for _ in range(400):
        await seq.add_frame(stream(valid_frame()))
        await seq.add_idle(random.choice([0, 0, 0, 1, 3]))
    await tb.finish()
