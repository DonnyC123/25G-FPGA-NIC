import random
from enum import Enum, auto

import cocotb

from rx_fifo.tb.rx_fifo_sequence_item import WORD_BYTES
from rx_fifo.tb.rx_fifo_test_base import RxFifoTestBase
from tb_utils.net.packets import split_words
from tb_utils.random_utils import pick, random_frame
from tb_utils.tb_common import reset_dut


class Action(Enum):
    FRAME = auto()
    EMPTY_TAIL = auto()
    DROP = auto()
    IDLE = auto()


ACTION_WEIGHTS = {
    Action.FRAME: 60,
    Action.EMPTY_TAIL: 5,
    Action.DROP: 10,
    Action.IDLE: 25,
}


@cocotb.test()
async def test_frame_sizes(dut) -> None:
    tb = await RxFifoTestBase.start(dut)
    seq = tb.sequence
    for length in range(1, 80):
        await seq.add_frame(random.randbytes(length))
        await seq.add_idle()
    await tb.finish()


@cocotb.test()
async def test_back_to_back(dut) -> None:
    tb = await RxFifoTestBase.start(dut)
    seq = tb.sequence
    for _ in range(60):
        await seq.add_frame(random_frame(1, 200))
    await tb.finish()


@cocotb.test()
async def test_gaps(dut) -> None:
    tb = await RxFifoTestBase.start(dut)
    seq = tb.sequence
    seq.gap_rate = 0.4
    for _ in range(40):
        await seq.add_frame(random_frame(1, 200))
    await tb.finish()


@cocotb.test()
async def test_drops(dut) -> None:
    tb = await RxFifoTestBase.start(dut)
    seq = tb.sequence
    frame = random.randbytes(40)
    for at in range(len(split_words(frame, WORD_BYTES))):
        for with_valid in (False, True):
            await seq.add_dropped(frame, at, with_valid)
            await seq.add_frame(random_frame(1, 200))
    await tb.finish()


@cocotb.test()
async def test_backpressure_cancels(dut) -> None:
    tb = await RxFifoTestBase.start(dut, ready_probability=0.1)
    seq = tb.sequence
    for _ in range(100):
        await seq.add_frame(random_frame(8, 300))
    await tb.finish()
    assert tb.driver.cancels > 0


@cocotb.test()
async def test_oversize_cancelled(dut) -> None:
    tb = await RxFifoTestBase.start(dut)
    seq = tb.sequence
    fifo_bytes = int(dut.FIFO_DEPTH.value) * int(dut.M_DATA_W.value) // 8
    await seq.add_frame(random.randbytes(fifo_bytes - 1))
    await seq.add_frame(random.randbytes(fifo_bytes))
    await seq.add_frame(random_frame(1, 200))
    await tb.finish()
    assert [f.cancelled for f in tb.model.items] == [False, True, False]


@cocotb.test()
async def test_reset_mid_frame(dut) -> None:
    tb = await RxFifoTestBase.start(dut)
    seq = tb.sequence
    for word in split_words(random.randbytes(40), WORD_BYTES)[:3]:
        await seq.add_word(word)
    await tb.wait_for_driver_done()
    await reset_dut(dut)
    await seq.add_frame(random_frame(1, 200))
    await tb.finish()


@cocotb.test()
async def test_random_traffic(dut) -> None:
    tb = await RxFifoTestBase.start(dut, ready_probability=0.5)
    seq = tb.sequence
    seq.gap_rate = 0.2
    for _ in range(300):
        match pick(ACTION_WEIGHTS):
            case Action.FRAME:
                await seq.add_frame(random_frame(1, 200))
            case Action.EMPTY_TAIL:
                await seq.add_frame(random.randbytes(8 * random.randint(1, 20)))
            case Action.DROP:
                frame = random_frame(1, 200)
                at = random.randrange(len(split_words(frame, WORD_BYTES)))
                await seq.add_dropped(frame, at, random.random() < 0.5)
            case Action.IDLE:
                await seq.add_idle(random.randint(1, 4))
    await tb.finish()
