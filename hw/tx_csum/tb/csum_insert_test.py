import random

import cocotb

from hw.tb_utils.tx_eth_stream import WORD_BYTES
from hw.tx_csum.tb.csum_insert_test_base import CsumInsertTestBase
from hw.tx_csum.tb.csum_model import CsumResult


def random_result(length: int) -> CsumResult:
    def pos() -> int:
        return random.choice([random.randrange(0, length + 16, 2), 24, 50, 70, length - 2, length - 1]) & ~1

    return CsumResult(
        random.getrandbits(1), max(pos(), 0), random.getrandbits(16), random.getrandbits(1), max(pos(), 0),
        random.getrandbits(16)
    )


async def run_frames(tb: CsumInsertTestBase, count: int, low: int, high: int) -> None:
    for _ in range(count):
        frame = random.randbytes(random.randint(low, high))
        await tb.sequence.add_frame_with_result(frame, random_result(len(frame)))
    await tb.finish()


@cocotb.test()
async def test_every_position(dut) -> None:
    tb = await CsumInsertTestBase.start(dut)
    for length in (60, 61, 64, 65, 100):
        for pos in range(0, length + 2, 2):
            frame = random.randbytes(length)
            result = CsumResult(1, pos, random.getrandbits(16), 1, (pos + 2 * WORD_BYTES) % length & ~1,
                                random.getrandbits(16))
            await tb.sequence.add_frame_with_result(frame, result)
    await tb.finish()


@cocotb.test()
async def test_back_to_back(dut) -> None:
    tb = await CsumInsertTestBase.start(dut)
    await run_frames(tb, 500, 1, 120)


@cocotb.test()
async def test_late_results(dut) -> None:
    tb = await CsumInsertTestBase.start(dut, max_delay=8)
    await run_frames(tb, 300, 1, 200)


@cocotb.test()
async def test_backpressure_and_gaps(dut) -> None:
    tb = await CsumInsertTestBase.start(dut, ready_probability=0.4, max_delay=4)
    tb.sequence.gap_rate = 0.3
    await run_frames(tb, 300, 1, 300)
