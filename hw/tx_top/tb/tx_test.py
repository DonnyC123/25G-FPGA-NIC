import random
from enum import Enum, auto

import cocotb

from hw.parser.tb.parser_frames import KNOWN_FRAMES, random_frame
from hw.tb_utils.axi_stream import AXI_WORD_BYTES
from hw.tb_utils.net.packets import pad
from hw.tb_utils.random_utils import pick
from hw.tx_csum.tb.csum_model import expected_csum
from hw.tx_top.tb.tx_test_base import TxTestBase

SLOW_AXI_PERIODS_PS = {"axi_clk": 8000, "eth_clk": 3102}


class Action(Enum):
    SHORT = auto()
    LONG = auto()
    IDLE = auto()


ACTION_WEIGHTS = {
    Action.SHORT: 40,
    Action.LONG: 40,
    Action.IDLE: 20,
}


def corrupt_checksums(frame: bytes, ext_stages: int) -> bytes:
    result = expected_csum(frame, ext_stages)
    out = bytearray(frame)
    for en, pos in ((result.ip_en, result.ip_pos), (result.l4_en, result.l4_pos)):
        if en:
            out[pos : pos + 2] = random.randbytes(2)
    return bytes(out)


@cocotb.test()
async def test_checksum_offload(dut) -> None:
    tb = await TxTestBase.start(dut)
    seq = tb.sequence
    fixed = 0
    for packet in KNOWN_FRAMES:
        frame = pad(bytes(packet))
        if len(frame) > tb.max_frame:
            continue
        sent = corrupt_checksums(frame, tb.model.ext_stages)
        fixed += sent != frame
        await seq.add_frame(sent)
        if tb.model.items[-1] != frame:
            raise AssertionError(f"model did not restore scapy checksums for {packet.summary()}")
    for _ in range(200):
        frame = random_frame()
        if len(frame) <= tb.max_frame:
            await seq.add_frame(corrupt_checksums(frame, tb.model.ext_stages))
    await tb.finish()
    cocotb.log.info("%d scapy frames sent with broken checksums and restored", fixed)


@cocotb.test()
async def test_frame_sizes(dut) -> None:
    tb = await TxTestBase.start(dut)
    seq = tb.sequence
    for length in range(1, min(130, tb.max_frame) + 1):
        await seq.add_frame(random.randbytes(length))
        await seq.add_idle()
    await tb.finish()


@cocotb.test()
async def test_axi_word_tails(dut) -> None:
    tb = await TxTestBase.start(dut)
    seq = tb.sequence
    for words in range(1, tb.max_frame // AXI_WORD_BYTES + 1):
        for tail in range(-1, 2):
            length = words * AXI_WORD_BYTES + tail
            if length <= tb.max_frame:
                await seq.add_frame(random.randbytes(length))
    await tb.finish()


@cocotb.test()
async def test_back_to_back(dut) -> None:
    tb = await TxTestBase.start(dut)
    seq = tb.sequence
    for _ in range(100):
        await seq.add_frame(tb.random_frame(300))
    await tb.finish()
    if tb.driver.stalls == 0:
        raise AssertionError("FIFO never pushed back on s_axi")


@cocotb.test()
async def test_ingress_gaps(dut) -> None:
    tb = await TxTestBase.start(dut)
    seq = tb.sequence
    seq.gap_rate = 0.5
    for _ in range(50):
        await seq.add_frame(tb.random_frame(300))
    await tb.finish()


@cocotb.test()
async def test_largest_frames(dut) -> None:
    tb = await TxTestBase.start(dut)
    seq = tb.sequence
    for _ in range(8):
        await seq.add_frame(random.randbytes(tb.max_frame))
    await tb.finish()


@cocotb.test()
async def test_slow_axi_clock(dut) -> None:
    tb = await TxTestBase.start(dut, SLOW_AXI_PERIODS_PS)
    seq = tb.sequence
    for _ in range(40):
        await seq.add_frame(tb.random_frame(300))
    await tb.finish()


@cocotb.test()
async def test_reset_recovery(dut) -> None:
    tb = await TxTestBase.start(dut)
    seq = tb.sequence
    for _ in range(10):
        await seq.add_frame(tb.random_frame(200))
    await tb.finish()
    await tb.reset()
    for _ in range(10):
        await seq.add_frame(tb.random_frame(200))
    await tb.finish()


@cocotb.test()
async def test_random_traffic(dut) -> None:
    tb = await TxTestBase.start(dut)
    seq = tb.sequence
    seq.gap_rate = 0.2
    for _ in range(200):
        match pick(ACTION_WEIGHTS):
            case Action.SHORT:
                await seq.add_frame(tb.random_frame(64))
            case Action.LONG:
                await seq.add_frame(tb.random_frame(1500))
            case Action.IDLE:
                await seq.add_idle(random.randint(1, 8))
    await tb.finish()
