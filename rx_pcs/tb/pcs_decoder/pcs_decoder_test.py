import random
from enum import Enum, auto

import cocotb

from common.pkg import pcs_pkg
from rx_pcs.tb.pcs_decoder.pcs_decoder_test_base import PcsDecoderTestBase
from tb_utils.net.pcs_blocks import (
    IDLE_BLOCKS,
    START_BLOCKS,
    TERM,
    PcsBlock,
    bad_tail,
    ctrl_block,
    data_block,
    encode,
    idle_block,
)
from tb_utils.random_utils import pick, random_frame

KNOWN_BLOCK_TYPES = (*IDLE_BLOCKS, *START_BLOCKS, *TERM)


class Action(Enum):
    FRAME = auto()
    TRUNCATED = auto()
    BAD_TERM = auto()
    IDLE = auto()
    BUBBLE = auto()
    DATA = auto()
    CTRL = auto()
    BAD_SYNC = auto()


ACTION_WEIGHTS = {
    Action.FRAME: 40,
    Action.TRUNCATED: 6,
    Action.BAD_TERM: 4,
    Action.IDLE: 20,
    Action.BUBBLE: 8,
    Action.DATA: 6,
    Action.CTRL: 12,
    Action.BAD_SYNC: 8,
}


def random_lane() -> int:
    return random.choice((0, 4))


def started(lane: int) -> list[PcsBlock]:
    return encode(random.randbytes(16), lane)[: 1 if lane == 0 else 2]


def opened(lane: int) -> list[PcsBlock]:
    return encode(random.randbytes(16), lane)[: 2 if lane == 0 else 3]


@cocotb.test()
async def test_sof_l0_every_term(dut) -> None:
    tb = await PcsDecoderTestBase.start(dut)
    seq = tb.sequence
    for length in range(24):
        await seq.add_frame(random.randbytes(length))
        await seq.add_idle(2)
    await tb.finish()


@cocotb.test()
async def test_sof_l4_every_term(dut) -> None:
    tb = await PcsDecoderTestBase.start(dut)
    seq = tb.sequence
    for length in range(4, 28):
        await seq.add_frame(random.randbytes(length), 4)
        await seq.add_idle(2)
    await tb.finish()


@cocotb.test()
async def test_ordered_set_sof_l4(dut) -> None:
    tb = await PcsDecoderTestBase.start(dut)
    seq = tb.sequence
    for length in (4, 8, 13, 20):
        blocks = encode(random.randbytes(length), 4)
        blocks[0] = ctrl_block(pcs_pkg.OS_SOF_L4, blocks[0].payload[1:])
        await seq.add_blocks(blocks)
        await seq.add_idle(2)
    await tb.finish()


@cocotb.test()
async def test_back_to_back_frames(dut) -> None:
    tb = await PcsDecoderTestBase.start(dut)
    seq = tb.sequence
    for _ in range(40):
        lane = random_lane()
        await seq.add_frame(random_frame(lane, 40), lane)
    await tb.finish()


@cocotb.test()
async def test_bubbles(dut) -> None:
    tb = await PcsDecoderTestBase.start(dut)
    seq = tb.sequence
    seq.bubble_rate = 0.3
    for _ in range(40):
        lane = random_lane()
        await seq.add_frame(random_frame(lane, 40), lane)
        await seq.add_idle(random.randint(0, 2))
    await tb.finish()


@cocotb.test()
async def test_idle_errors(dut) -> None:
    tb = await PcsDecoderTestBase.start(dut)
    seq = tb.sequence
    await seq.add_blocks([ctrl_block(t, bytes([0x12] * 7)) for t in IDLE_BLOCKS])
    await seq.add_blocks([ctrl_block(t) for t in TERM])
    await seq.add_blocks(
        [
            ctrl_block(0x00),
            ctrl_block(0x5A),
            data_block(bytes([0xAB] * 8)),
            PcsBlock(0b00, bytes(8)),
            PcsBlock(0b11, bytes(8)),
            bad_tail(ctrl_block(TERM[2])),
            bad_tail(idle_block()),
        ]
    )
    await seq.add_frame(random.randbytes(20))
    await tb.finish()


@cocotb.test()
async def test_mid_frame_faults(dut) -> None:
    tb = await PcsDecoderTestBase.start(dut)
    seq = tb.sequence
    for lane in (0, 4):
        await seq.add_blocks([*opened(lane), PcsBlock(0b11, bytes(8))])
        await seq.add_frame(random.randbytes(17), lane)

        await seq.add_blocks(opened(lane))
        await seq.add_idle()
        await seq.add_frame(random.randbytes(17), lane)

        await seq.add_blocks([*started(lane), ctrl_block(pcs_pkg.OS_OS)])
        await seq.add_frame(random.randbytes(17), lane)

        await seq.add_blocks([*opened(lane), ctrl_block(0x5A)])
        await seq.add_idle()

        await seq.add_blocks([*opened(lane), bad_tail(ctrl_block(TERM[3]))])
        await seq.add_frame(random.randbytes(17), lane)

        await seq.add_blocks(opened(lane))
        await seq.add_frame(random.randbytes(21), 0)

        await seq.add_blocks(opened(lane))
        await seq.add_frame(random.randbytes(21), 4)
        await seq.add_idle(2)

    sof_l4 = encode(random.randbytes(8), 4)[0]
    await seq.add_blocks([sof_l4, ctrl_block(pcs_pkg.SOF_L0)])
    await seq.add_frame(random.randbytes(9))

    await seq.add_blocks([sof_l4, PcsBlock(0b00, bytes(8))])
    await seq.add_frame(random.randbytes(9), 4)
    await tb.finish()


@cocotb.test()
async def test_alignment_loss(dut) -> None:
    tb = await PcsDecoderTestBase.start(dut)
    seq = tb.sequence

    blocks = encode(random.randbytes(26))
    await seq.add_blocks(blocks[:2])
    await seq.add_blocks(blocks[2:3], aligned=False)
    await seq.add_blocks(blocks[3:])
    await seq.add_frame(random.randbytes(12))

    await seq.add_blocks(encode(random.randbytes(12), 4)[:3])
    await seq.add_idle(aligned=False)
    await seq.add_frame(random.randbytes(12), 4)

    await seq.add_blocks(encode(random.randbytes(8), 4)[:1])
    await seq.add_bubble(aligned=False)
    await seq.add_blocks([data_block(random.randbytes(8))])
    await seq.add_frame(random.randbytes(12))

    await seq.add_blocks(encode(random.randbytes(10), 4))
    await seq.add_idle(aligned=False)
    await seq.add_frame(random.randbytes(12))

    await seq.add_blocks(encode(random.randbytes(16))[:2])
    await seq.add_bubble(aligned=False)
    await seq.add_frame(random.randbytes(12))

    await seq.add_blocks(
        [
            ctrl_block(TERM[3]),
            data_block(random.randbytes(8)),
            PcsBlock(0b00, bytes(8)),
            *encode(random.randbytes(12)),
        ],
        aligned=False,
    )
    await seq.add_frame(random.randbytes(12))
    await tb.finish()


@cocotb.test()
async def test_random_traffic(dut) -> None:
    tb = await PcsDecoderTestBase.start(dut)
    seq = tb.sequence

    for _ in range(400):
        aligned = random.random() > 0.03
        lane = random_lane()
        match pick(ACTION_WEIGHTS):
            case Action.FRAME:
                frame = random_frame(lane, 48)
                await seq.add_frame(frame, lane, aligned=aligned)
            case Action.TRUNCATED:
                frame = random_frame(lane, 24)
                await seq.add_blocks(encode(frame, lane)[:-1], aligned=aligned)
            case Action.BAD_TERM:
                length = (
                    lane
                    + pcs_pkg.PCS_PAYLOAD_BYTES * random.randint(0, 2)
                    + random.randint(0, len(TERM) - 2)
                )
                blocks = encode(random.randbytes(length), lane)
                blocks[-1] = bad_tail(blocks[-1])
                await seq.add_blocks(blocks, aligned=aligned)
            case Action.IDLE:
                await seq.add_idle(random.randint(1, 3), aligned=aligned)
            case Action.BUBBLE:
                await seq.add_bubble(random.randint(1, 3), aligned=aligned)
            case Action.DATA:
                await seq.add_blocks([data_block(random.randbytes(8))], aligned=aligned)
            case Action.CTRL:
                block_type = random.choice([*KNOWN_BLOCK_TYPES, random.randrange(256)])
                block = ctrl_block(block_type, random.randbytes(7))
                await seq.add_blocks([block], aligned=aligned)
            case Action.BAD_SYNC:
                sync = random.choice([0b00, 0b11])
                block = PcsBlock(sync, random.randbytes(8))
                await seq.add_blocks([block], aligned=aligned)

    await tb.finish()
