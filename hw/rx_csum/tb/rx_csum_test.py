import random

import cocotb
from scapy.layers.inet import IP, TCP, UDP
from scapy.layers.inet6 import IPv6
from scapy.layers.l2 import Dot1Q, Ether
from scapy.packet import Packet, Raw

from hw.rx_csum.tb.rx_csum_model import linux_validates
from hw.rx_csum.tb.rx_csum_test_base import RxCsumTestBase
from hw.rx_parser.tb.parser_frames import KNOWN_FRAMES, valid_frame
from hw.tb_utils.net.packets import ETH_MIN_LEN, add_fcs, pad
from hw.tb_utils.tx_eth_stream import WORD_BYTES

JUMBO_LEN = 9014


def stream(data: bytes) -> bytes:
    return add_fcs(pad(data))


def eth(vlan: bool) -> Packet:
    packet = Ether(src="02:00:00:00:00:01", dst="02:00:00:00:00:02")
    return packet / Dot1Q() if vlan else packet


def l4_packets() -> list[Packet]:
    packets = []
    for vlan in (False, True):
        v4 = IP(src="10.0.0.1", dst="10.0.0.2")
        v6 = IPv6(src="fe80::1", dst="fe80::2")
        for l3 in (v4, v6):
            for l4 in (TCP(sport=1234, dport=80), UDP(sport=5353, dport=53)):
                for size in (0, 1, 7, 100, 1001):
                    packets.append(eth(vlan) / l3 / l4 / Raw(random.randbytes(size)))
    return packets


@cocotb.test()
async def test_every_frame_length(dut) -> None:
    tb = await RxCsumTestBase.start(dut)
    seq = tb.sequence
    for length in range(ETH_MIN_LEN, ETH_MIN_LEN + 3 * WORD_BYTES):
        await seq.add_frame(add_fcs(random.randbytes(length)))
        await seq.add_idle(2)
    await tb.finish()


@cocotb.test()
async def test_known_frames(dut) -> None:
    tb = await RxCsumTestBase.start(dut)
    seq = tb.sequence
    for packet in KNOWN_FRAMES:
        await seq.add_frame(stream(bytes(packet)))
        await seq.add_idle(2)
    await tb.finish()


@cocotb.test()
async def test_jumbo_all_ones(dut) -> None:
    tb = await RxCsumTestBase.start(dut)
    seq = tb.sequence
    await seq.add_frame(add_fcs(b"\xff" * JUMBO_LEN))
    await seq.add_frame(add_fcs(random.randbytes(JUMBO_LEN)))
    await tb.finish()


@cocotb.test()
async def test_back_to_back_frames(dut) -> None:
    tb = await RxCsumTestBase.start(dut)
    seq = tb.sequence
    for _ in range(100):
        await seq.add_frame(stream(valid_frame()))
    await tb.finish()


@cocotb.test()
async def test_random_traffic(dut) -> None:
    tb = await RxCsumTestBase.start(dut)
    seq = tb.sequence
    seq.bubble_rate = 0.2
    for _ in range(300):
        await seq.add_frame(stream(valid_frame()))
        await seq.add_idle(random.choice([0, 0, 0, 1, 3]))
    await tb.finish()


@cocotb.test()
async def test_linux_validates_tcp_udp(dut) -> None:
    tb = await RxCsumTestBase.start(dut)
    seq = tb.sequence
    seq.bubble_rate = 0.1
    packets = l4_packets()
    for packet in packets:
        await seq.add_frame(stream(bytes(packet)))
    await tb.finish()
    assert len(tb.monitor.items) == len(packets)
    for frame, csum in tb.monitor.items:
        assert linux_validates(frame, csum), f"Linux rejects {len(frame)} byte frame"
