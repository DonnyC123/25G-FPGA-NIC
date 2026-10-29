import random
from enum import Enum, auto

import cocotb

from tb_utils.random_utils import pick, random_frame
from tx_mac.tb.tx_framer.tx_framer_test_base import TxFramerTestBase


class Action(Enum):
    SHORT = auto()
    LONG = auto()
    IDLE = auto()


ACTION_WEIGHTS = {
    Action.SHORT: 40,
    Action.LONG: 40,
    Action.IDLE: 20,
}


@cocotb.test()
async def test_frame_sizes(dut) -> None:
    tb = await TxFramerTestBase.start(dut)
    seq = tb.sequence
    for length in range(0, 130):
        await seq.add_frame(random.randbytes(length))
        await seq.add_idle()
    await tb.finish()


@cocotb.test()
async def test_back_to_back(dut) -> None:
    tb = await TxFramerTestBase.start(dut)
    seq = tb.sequence
    for _ in range(100):
        await seq.add_frame(random_frame(0, 200))
    await tb.finish()


@cocotb.test()
async def test_gearbox_stalls(dut) -> None:
    tb = await TxFramerTestBase.start(dut, ready_probability=0.97)
    seq = tb.sequence
    for _ in range(100):
        await seq.add_frame(random_frame(0, 200))
    await tb.finish()


@cocotb.test()
async def test_backpressure(dut) -> None:
    tb = await TxFramerTestBase.start(dut, ready_probability=0.3)
    seq = tb.sequence
    for _ in range(60):
        await seq.add_frame(random_frame(0, 200))
    await tb.finish()


@cocotb.test()
async def test_random_traffic(dut) -> None:
    tb = await TxFramerTestBase.start(dut, ready_probability=0.8)
    seq = tb.sequence
    for _ in range(300):
        match pick(ACTION_WEIGHTS):
            case Action.SHORT:
                await seq.add_frame(random_frame(0, 64))
            case Action.LONG:
                await seq.add_frame(random_frame(65, 300))
            case Action.IDLE:
                await seq.add_idle(random.randint(1, 4))
    await tb.finish()
