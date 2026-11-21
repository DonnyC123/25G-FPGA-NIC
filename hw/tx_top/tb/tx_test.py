import random
from enum import Enum, auto

import cocotb

from hw.rx_parser.tb.parser_frames import KNOWN_FRAMES, random_frame
from hw.tb_utils.axi_stream import AXI_WORD_BYTES
from hw.tb_utils.net.packets import pad
from hw.tb_utils.random_utils import pick
from hw.tx_csum.tb.tx_offload_model import TxMeta, linux_meta, seed
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


def nonzero_csum(frame: bytes, meta: TxMeta) -> bytes:
    pos = meta.csum_pos
    if not meta.csum or frame[pos : pos + 2] != b"\0\0":
        return frame
    return frame[:pos] + b"\xff\xff" + frame[pos + 2 :]


def split_frame(frame: bytes) -> list[bytes]:
    count = min(len(frame) - 1, random.randint(0, 3))
    cuts = sorted(random.sample(range(1, len(frame)), count))
    return [frame[a:b] for a, b in zip([0, *cuts], [*cuts, len(frame)])]


def random_meta(frame: bytes) -> TxMeta:
    start = random.randint(0, len(frame) + 2)
    offset = random.choice([0, 1, 6, 16, random.randint(0, 64)])
    return TxMeta(random.random() < 0.8, start, offset, len(frame))


@cocotb.test()
async def test_checksum_offload(dut) -> None:
    tb = await TxTestBase.start(dut)
    seeded = 0
    frames = [pad(bytes(packet)) for packet in KNOWN_FRAMES]
    frames += [random_frame() for _ in range(200)]
    for frame in frames:
        if len(frame) > tb.max_frame:
            continue
        meta = linux_meta(frame)
        sent = seed(frame, meta) if meta.csum else frame
        seeded += sent != frame
        await tb.send(sent, meta)
        if tb.model.items[-1] != nonzero_csum(frame, meta):
            raise AssertionError(f"model did not restore the checksum of {frame[:64].hex()}")
    await tb.finish()
    cocotb.log.info("%d frames sent with a seeded checksum and restored", seeded)


@cocotb.test()
async def test_passthrough(dut) -> None:
    tb = await TxTestBase.start(dut)
    for packet in KNOWN_FRAMES:
        frame = pad(bytes(packet))
        if len(frame) <= tb.max_frame:
            await tb.send(frame)
    await tb.finish()


@cocotb.test()
async def test_generic_offsets(dut) -> None:
    tb = await TxTestBase.start(dut)
    for _ in range(300):
        frame = tb.random_frame(400)
        await tb.send(frame, random_meta(frame))
    await tb.finish()


@cocotb.test()
async def test_metadata_only(dut) -> None:
    tb = await TxTestBase.start(dut)
    for _ in range(5):
        await tb.sequence.add_frame(TxMeta().pack())
        await tb.send(tb.random_frame(100))
    await tb.finish()


@cocotb.test()
async def test_scatter_gather(dut) -> None:
    tb = await TxTestBase.start(dut)
    frames = [pad(bytes(packet)) for packet in KNOWN_FRAMES]
    frames += [random_frame() for _ in range(100)]
    for frame in frames:
        if len(frame) > tb.max_frame:
            continue
        meta = linux_meta(frame)
        sent = seed(frame, meta) if meta.csum else frame
        await tb.sequence.add_segments([meta.pack(), *split_frame(sent)])
    await tb.finish()


@cocotb.test()
async def test_frame_sizes(dut) -> None:
    tb = await TxTestBase.start(dut)
    seq = tb.sequence
    for length in range(1, min(130, tb.max_frame) + 1):
        await tb.send(random.randbytes(length))
        await seq.add_idle()
    await tb.finish()


@cocotb.test()
async def test_axi_word_tails(dut) -> None:
    tb = await TxTestBase.start(dut)
    for words in range(1, tb.max_frame // AXI_WORD_BYTES + 1):
        for tail in range(-1, 2):
            length = words * AXI_WORD_BYTES + tail
            if length <= tb.max_frame:
                await tb.send(random.randbytes(length))
    await tb.finish()


@cocotb.test()
async def test_back_to_back(dut) -> None:
    tb = await TxTestBase.start(dut)
    for _ in range(100):
        await tb.send(tb.random_frame(300))
    await tb.finish()
    if tb.driver.stalls == 0:
        raise AssertionError("FIFO never pushed back on s_axi")


@cocotb.test()
async def test_ingress_gaps(dut) -> None:
    tb = await TxTestBase.start(dut)
    seq = tb.sequence
    seq.gap_rate = 0.5
    for _ in range(50):
        await tb.send(tb.random_frame(300))
    await tb.finish()


@cocotb.test()
async def test_largest_frames(dut) -> None:
    tb = await TxTestBase.start(dut)
    for _ in range(8):
        await tb.send(random.randbytes(tb.max_frame))
    await tb.finish()


@cocotb.test()
async def test_slow_axi_clock(dut) -> None:
    tb = await TxTestBase.start(dut, SLOW_AXI_PERIODS_PS)
    for _ in range(40):
        await tb.send(tb.random_frame(300))
    await tb.finish()


@cocotb.test()
async def test_reset_recovery(dut) -> None:
    tb = await TxTestBase.start(dut)
    for _ in range(10):
        await tb.send(tb.random_frame(200))
    await tb.finish()
    await tb.reset()
    for _ in range(10):
        await tb.send(tb.random_frame(200))
    await tb.finish()


@cocotb.test()
async def test_random_traffic(dut) -> None:
    tb = await TxTestBase.start(dut)
    seq = tb.sequence
    seq.gap_rate = 0.2
    for _ in range(200):
        match pick(ACTION_WEIGHTS):
            case Action.SHORT:
                await tb.send(tb.random_frame(64))
            case Action.LONG:
                await tb.send(tb.random_frame(1500))
            case Action.IDLE:
                await seq.add_idle(random.randint(1, 8))
    await tb.finish()
