import random

import cocotb

from hw.common.pkg.pcs_pkg import PCS_BLOCK_W
from hw.rx_pcs.tb.alignment_finder.alignment_finder_test_base import (
    AlignmentFinderTestBase,
)


@cocotb.test()
@cocotb.parametrize(offset=list(range(PCS_BLOCK_W)))
async def test_gain_alignment(dut, offset):
    tb = await AlignmentFinderTestBase.start(dut)
    await tb.sequence.add_garbage(offset)
    await tb.run_until(True)
    await tb.finish()

    rises, falls = tb.edges()
    assert len(rises) == 1 and not falls
    tb.check_acquired(rises[0], -1, offset)


@cocotb.test()
@cocotb.parametrize(offset=[1, 33, 65])
async def test_gain_alignment_slow_pma(dut, offset):
    tb = await AlignmentFinderTestBase.start(dut, slip_latency=8, bubble_rate=0.25)
    await tb.sequence.add_garbage(offset)
    await tb.run_until(True)
    await tb.finish()

    rises, falls = tb.edges()
    assert len(rises) == 1 and not falls
    tb.check_acquired(rises[0], -1, offset)


@cocotb.test()
async def test_hold_alignment(dut):
    tb = await AlignmentFinderTestBase.start(dut)
    seq = tb.sequence
    edge = tb.bad_count - 1

    await seq.add_good(tb.good_count)
    for _ in range(4):
        await seq.add_window(tb.bad_window, random.sample(range(tb.bad_window), edge))
    await seq.add_window(tb.bad_window, range(tb.bad_window - edge, tb.bad_window))
    await seq.add_window(tb.bad_window, range(edge))
    await seq.add_good(tb.good_count)
    await tb.finish()

    rises, falls = tb.edges()
    assert rises == [tb.good_count - 1] and not falls
    assert not tb.slips(0, len(tb.headers()))


@cocotb.test()
async def test_lose_alignment(dut):
    tb = await AlignmentFinderTestBase.start(dut)
    seq = tb.sequence
    bad = sorted(random.sample(range(tb.bad_window), tb.bad_count))

    await seq.add_good(tb.good_count)
    await seq.add_window(tb.bad_window, bad)
    await tb.finish()

    rises, falls = tb.edges()
    assert rises[0] == tb.good_count - 1
    lost_at = tb.good_count + bad[-1]
    assert falls[0] == lost_at, f"lost on header {falls[0]}, expected {lost_at}"
    assert not tb.headers()[falls[0]].bitslip


@cocotb.test()
async def test_lose_and_regain(dut):
    tb = await AlignmentFinderTestBase.start(dut)
    await tb.run_until(True)

    for round in range(4):
        if round % 2:
            await tb.lose_by_glitch(random.randint(1, PCS_BLOCK_W - 1))
        else:
            await tb.lose_by_bad_headers()

    await tb.finish()
