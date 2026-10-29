import random
from enum import Enum, auto

import cocotb

from rx_mac.tb.crc_checker.crc_checker_sequence_item import WORD_BYTES
from rx_mac.tb.crc_checker.crc_checker_test_base import CrcCheckerTestBase
from tb_utils.net.packets import add_fcs, split_words
from tb_utils.random_utils import pick


class Action(Enum):
    GOOD = auto()
    BAD = auto()
    DROP = auto()
    IDLE = auto()


ACTION_WEIGHTS = {
    Action.GOOD: 50,
    Action.BAD: 15,
    Action.DROP: 16,
    Action.IDLE: 19,
}


def good_frame(length: int) -> bytes:
    return add_fcs(random.randbytes(length))


def bad_frame(length: int) -> bytes:
    frame = bytearray(good_frame(length))
    frame[random.randrange(len(frame))] ^= 1 << random.randrange(8)
    return bytes(frame)


@cocotb.test()
async def test_every_tail_length(dut) -> None:
    tb = await CrcCheckerTestBase.start(dut)
    seq = tb.sequence
    for length in range(1, 3 * WORD_BYTES + 1):
        await seq.add_frame(good_frame(length))
        await seq.add_idle(2)
    await tb.finish()


@cocotb.test()
async def test_bad_fcs_dropped(dut) -> None:
    tb = await CrcCheckerTestBase.start(dut)
    seq = tb.sequence
    for length in range(1, 3 * WORD_BYTES + 1):
        await seq.add_frame(bad_frame(length))
        await seq.add_idle(2)
        await seq.add_frame(good_frame(length))
        await seq.add_idle(2)
    await tb.finish()


@cocotb.test()
async def test_back_to_back_frames(dut) -> None:
    tb = await CrcCheckerTestBase.start(dut)
    seq = tb.sequence
    for _ in range(30):
        await seq.add_frame(good_frame(random.randint(1, 40)))
    await tb.finish()


@cocotb.test()
async def test_bubbles(dut) -> None:
    tb = await CrcCheckerTestBase.start(dut)
    seq = tb.sequence
    seq.bubble_rate = 0.3
    for _ in range(30):
        make = good_frame if random.random() < 0.7 else bad_frame
        await seq.add_frame(make(random.randint(1, 40)))
        await seq.add_idle(random.randint(0, 2))
    await tb.finish()


@cocotb.test()
async def test_drop_mid_frame(dut) -> None:
    tb = await CrcCheckerTestBase.start(dut)
    seq = tb.sequence
    for at in range(1, 4):
        words = split_words(good_frame(40), WORD_BYTES)
        await seq.add_words(words[:at], last=False)
        await seq.add_drop()
        await seq.add_idle(2)
        await seq.add_frame(good_frame(20))
        await seq.add_idle(2)
    await tb.finish()


@cocotb.test()
async def test_drop_with_valid(dut) -> None:
    tb = await CrcCheckerTestBase.start(dut)
    seq = tb.sequence
    for at in range(1, 4):
        words = split_words(good_frame(40), WORD_BYTES)
        await seq.add_words(words[:at], last=False)
        await seq.add_drop(words[at])
        await seq.add_idle(2)
        await seq.add_frame(good_frame(20))
        await seq.add_idle(2)
    await tb.finish()


@cocotb.test()
async def test_drop_while_idle(dut) -> None:
    tb = await CrcCheckerTestBase.start(dut)
    seq = tb.sequence
    await seq.add_drop()
    await seq.add_idle(2)
    await seq.add_frame(good_frame(20))
    await tb.finish()


@cocotb.test()
async def test_random_traffic(dut) -> None:
    tb = await CrcCheckerTestBase.start(dut)
    seq = tb.sequence
    seq.bubble_rate = 0.1
    for _ in range(200):
        match pick(ACTION_WEIGHTS):
            case Action.GOOD:
                await seq.add_frame(good_frame(random.randint(1, 64)))
            case Action.BAD:
                await seq.add_frame(bad_frame(random.randint(1, 64)))
            case Action.DROP:
                words = split_words(good_frame(random.randint(9, 64)), WORD_BYTES)
                head = words[: random.randrange(1, len(words))]
                await seq.add_words(head, last=False)
                await seq.add_drop()
            case Action.IDLE:
                await seq.add_idle(random.randint(1, 3))
    await tb.finish()
