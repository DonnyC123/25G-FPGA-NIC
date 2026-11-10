import random

import cocotb
from scapy.layers.inet import IP, TCP, UDP
from scapy.layers.inet6 import IPv6
from scapy.layers.l2 import ARP, LLC, Dot1AD, Dot1Q, Dot3, Ether
from scapy.packet import Raw

from hw.common.pkg.parser_pkg import (
    ETH_TYPE_OFF,
    ETHERTYPE_QINQ,
    ETHERTYPE_VLAN,
    VLAN_TAG_BYTES,
)
from hw.parser.tb.eth_stage_test_base import EthStageTestBase
from hw.tb_utils.net.packets import pad

KNOWN_FRAMES = [
    Ether() / IP() / TCP(),
    Ether() / IPv6() / TCP() / Raw(b"x" * 1400),
    Ether() / ARP(),
    Ether() / Dot1Q(vlan=5) / IP() / UDP(),
    Ether() / Dot1Q(vlan=7) / IPv6() / TCP(),
    Ether() / Dot1AD(vlan=1) / Dot1Q(vlan=2) / IP() / TCP(),
    Ether() / Dot1Q(vlan=1) / Dot1Q(vlan=2) / IPv6() / TCP(),
    Ether() / Dot1AD(vlan=1) / Dot1Q(vlan=2) / Dot1Q(vlan=3) / IP() / TCP(),
    Dot3() / LLC(),
]

TPIDS = [ETHERTYPE_VLAN, ETHERTYPE_QINQ, 0x9100]
INNER_TYPES = [0x0800, 0x86DD, 0x0806, 0x88CC, 0x0600, 0x05FF, 0x0000, 0x002E]


def random_frame(max_tags: int, length: int) -> bytes:
    frame = bytearray(random.randbytes(ETH_TYPE_OFF))
    for _ in range(random.randint(0, max_tags)):
        frame += random.choice(TPIDS).to_bytes(2, "big") + random.randbytes(VLAN_TAG_BYTES - 2)
    inner = random.choice(INNER_TYPES + [random.getrandbits(16)])
    frame += inner.to_bytes(2, "big")
    frame += random.randbytes(max(0, length - len(frame)))
    return bytes(frame[:length])


@cocotb.test()
async def test_known_frames(dut) -> None:
    tb = await EthStageTestBase.start(dut)
    for packet in KNOWN_FRAMES:
        await tb.sequence.add_frame(pad(bytes(packet)))
    await tb.finish()


@cocotb.test()
async def test_short_frames(dut) -> None:
    tb = await EthStageTestBase.start(dut)
    for packet in KNOWN_FRAMES:
        frame = pad(bytes(packet))
        for length in range(1, 33):
            await tb.sequence.add_frame(frame[:length])
    await tb.finish()


@cocotb.test()
async def test_random_backpressure(dut) -> None:
    tb = await EthStageTestBase.start(dut, ready_probability=0.5)
    tb.sequence.gap_rate = 0.3
    for _ in range(1500):
        await tb.sequence.add_frame(random_frame(4, random.choice([random.randint(1, 80), random.randint(60, 1514)])))
    await tb.finish()


@cocotb.test()
async def test_back_to_back(dut) -> None:
    tb = await EthStageTestBase.start(dut)
    for _ in range(500):
        await tb.sequence.add_frame(random_frame(3, random.randint(1, 100)))
    await tb.finish()
