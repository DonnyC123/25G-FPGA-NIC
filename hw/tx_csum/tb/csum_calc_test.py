import cocotb
from scapy.layers.inet import IP, TCP, UDP
from scapy.layers.inet6 import IPv6, IPv6ExtHdrHopByHop
from scapy.layers.l2 import Dot1Q, Ether
from scapy.packet import Raw

from hw.parser.tb.parser_frames import KNOWN_FRAMES, SCAPY_DIFFERS_FRAMES, random_frame
from hw.tb_utils.net.packets import pad
from hw.tx_csum.tb.csum_calc_test_base import CsumCalcTestBase
from hw.tx_csum.tb.csum_model import expected_csum, force_zero_csum

ZERO_CSUM_BASES = [
    Ether() / IP() / TCP() / Raw(b"\0" * 20),
    Ether() / IP() / UDP() / Raw(b"\0" * 20),
    Ether() / IPv6() / TCP() / Raw(b"\0" * 21),
    Ether() / IPv6() / UDP() / Raw(b"\0" * 20),
    Ether() / Dot1Q() / IPv6() / IPv6ExtHdrHopByHop() / UDP() / Raw(b"\0" * 300),
]


@cocotb.test()
async def test_model_matches_scapy(dut) -> None:
    tb = await CsumCalcTestBase.start(dut)
    checked = 0
    for packet in KNOWN_FRAMES:
        if any(packet is other for other in SCAPY_DIFFERS_FRAMES):
            continue
        frame = pad(bytes(packet))
        want = expected_csum(frame, tb.model.ext_stages, tb.model.opt_stages)
        if want.ip_en:
            assert int.from_bytes(frame[want.ip_pos : want.ip_pos + 2], "big") == want.ip_csum, packet.summary()
            checked += 1
        if want.l4_en:
            assert int.from_bytes(frame[want.l4_pos : want.l4_pos + 2], "big") == want.l4_csum, packet.summary()
            checked += 1
    assert checked > 20, checked
    cocotb.log.info("model agrees with scapy on %d checksums", checked)


@cocotb.test()
async def test_known_frames(dut) -> None:
    tb = await CsumCalcTestBase.start(dut)
    for packet in KNOWN_FRAMES:
        await tb.sequence.add_frame(pad(bytes(packet)))
    await tb.finish()


@cocotb.test()
async def test_zero_checksum(dut) -> None:
    tb = await CsumCalcTestBase.start(dut)
    for packet in ZERO_CSUM_BASES:
        frame = force_zero_csum(pad(bytes(packet)), tb.model.ext_stages, tb.model.opt_stages)
        result = expected_csum(frame, tb.model.ext_stages, tb.model.opt_stages)
        assert result.l4_en and result.l4_csum in (0x0000, 0xFFFF), (packet.summary(), result)
        await tb.sequence.add_frame(frame)
    await tb.finish()


@cocotb.test()
async def test_truncated_known_frames(dut) -> None:
    tb = await CsumCalcTestBase.start(dut)
    for packet in KNOWN_FRAMES:
        frame = pad(bytes(packet))
        for length in range(1, min(len(frame), 140)):
            await tb.sequence.add_frame(frame[:length])
    await tb.finish()


@cocotb.test()
async def test_random_frames(dut) -> None:
    tb = await CsumCalcTestBase.start(dut)
    for _ in range(3000):
        await tb.sequence.add_frame(random_frame())
    await tb.finish()


@cocotb.test()
async def test_random_backpressure(dut) -> None:
    tb = await CsumCalcTestBase.start(dut, ready_probability=0.4)
    tb.sequence.gap_rate = 0.3
    for _ in range(1500):
        await tb.sequence.add_frame(random_frame())
    await tb.finish()
