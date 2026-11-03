import random
from enum import Enum, auto

import cocotb

from hw.tb_utils.axi_stream import AXI_WORD_BYTES as WORD_BYTES
from hw.tb_utils.net.packets import split_words
from hw.tb_utils.random_utils import pick
from hw.tb_utils.tb_common import reset_dut
from hw.tx_fifo.tb.tx_fifo_test_base import TxFifoTestBase


class Action(Enum):
    FRAME = auto()
    FULL_WORD_END = auto()
    IDLE = auto()


ACTION_WEIGHTS = {
    Action.FRAME: 65,
    Action.FULL_WORD_END: 10,
    Action.IDLE: 25,
}


@cocotb.test()
async def test_frame_sizes(dut) -> None:
    tb = await TxFifoTestBase.start(dut)
    seq = tb.sequence
    for length in range(1, min(200, tb.max_frame) + 1):
        await seq.add_frame(random.randbytes(length))
        await seq.add_idle()
    await tb.finish()


@cocotb.test()
async def test_back_to_back(dut) -> None:
    tb = await TxFifoTestBase.start(dut)
    seq = tb.sequence
    for _ in range(60):
        await seq.add_frame(tb.random_frame(500))
    await tb.finish()


@cocotb.test()
async def test_full_word_end(dut) -> None:
    tb = await TxFifoTestBase.start(dut)
    seq = tb.sequence
    for words in range(1, tb.max_frame // WORD_BYTES + 1):
        await seq.add_frame(random.randbytes(words * WORD_BYTES))
    await tb.finish()


@cocotb.test()
async def test_gaps(dut) -> None:
    tb = await TxFifoTestBase.start(dut)
    seq = tb.sequence
    seq.gap_rate = 0.4
    for _ in range(40):
        await seq.add_frame(tb.random_frame(500))
    await tb.finish()


@cocotb.test()
async def test_backpressure(dut) -> None:
    tb = await TxFifoTestBase.start(dut, ready_probability=0.2)
    seq = tb.sequence
    for _ in range(60):
        await seq.add_frame(tb.random_frame(500))
    await tb.finish()


@cocotb.test()
async def test_max_frame(dut) -> None:
    tb = await TxFifoTestBase.start(dut, ready_probability=0.5)
    seq = tb.sequence
    for _ in range(3):
        await seq.add_frame(random.randbytes(tb.max_frame))
    await tb.finish()


@cocotb.test()
async def test_reset_mid_frame(dut) -> None:
    tb = await TxFifoTestBase.start(dut)
    seq = tb.sequence
    for word in split_words(random.randbytes(3 * WORD_BYTES), WORD_BYTES):
        await seq.add_word(word)
    await tb.wait_for_driver_done()
    await reset_dut(dut)
    await seq.add_frame(tb.random_frame(200))
    await tb.finish()


@cocotb.test()
async def test_random_traffic(dut) -> None:
    tb = await TxFifoTestBase.start(dut, ready_probability=0.5)
    seq = tb.sequence
    seq.gap_rate = 0.2
    for _ in range(300):
        match pick(ACTION_WEIGHTS):
            case Action.FRAME:
                await seq.add_frame(tb.random_frame(500))
            case Action.FULL_WORD_END:
                words = random.randint(1, tb.max_frame // WORD_BYTES)
                await seq.add_frame(random.randbytes(words * WORD_BYTES))
            case Action.IDLE:
                await seq.add_idle(random.randint(1, 4))
    await tb.finish()
