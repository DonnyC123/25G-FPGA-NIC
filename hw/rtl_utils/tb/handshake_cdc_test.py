import random

import cocotb
from cocotb.triggers import ClockCycles, ReadOnly, RisingEdge

from hw.tb_utils.tb_common import start_clock

DATA_W = 32
WORDS = 200
SETTLE_CYCLES = 16


async def reset(dut) -> None:
    dut.src_rst.value = 1
    dut.dst_rst.value = 1
    dut.src_valid_i.value = 0
    dut.src_data_i.value = 0
    await ClockCycles(dut.src_clk, 4)
    await ClockCycles(dut.dst_clk, 4)
    dut.src_rst.value = 0
    dut.dst_rst.value = 0
    await RisingEdge(dut.src_clk)


async def send(dut, words: list[int], idle_rate: float) -> None:
    for word in words:
        while random.random() < idle_rate:
            await RisingEdge(dut.src_clk)
        dut.src_data_i.value = word
        dut.src_valid_i.value = 1
        while True:
            await ReadOnly()
            taken = bool(dut.src_ready_o.value)
            await RisingEdge(dut.src_clk)
            if taken:
                break
        dut.src_valid_i.value = 0
        dut.src_data_i.value = random.getrandbits(DATA_W)


async def receive(dut, got: list[int]) -> None:
    while True:
        await RisingEdge(dut.dst_clk)
        await ReadOnly()
        if dut.dst_valid_o.value:
            got.append(int(dut.dst_data_o.value))


async def run(dut, src_period_ps: int, dst_period_ps: int, idle_rate: float) -> None:
    start_clock(dut.src_clk, src_period_ps, random.randrange(src_period_ps))
    start_clock(dut.dst_clk, dst_period_ps, random.randrange(dst_period_ps))
    await reset(dut)
    words = [random.getrandbits(DATA_W) for _ in range(WORDS)]
    got: list[int] = []
    cocotb.start_soon(receive(dut, got))
    await send(dut, words, idle_rate)
    await ClockCycles(dut.dst_clk, SETTLE_CYCLES)
    await ClockCycles(dut.src_clk, SETTLE_CYCLES)
    assert got == words, f"sent {len(words)} words, received {len(got)}"


@cocotb.test()
async def test_fast_src_slow_dst(dut) -> None:
    await run(dut, 4000, 20000, 0.0)


@cocotb.test()
async def test_slow_src_fast_dst(dut) -> None:
    await run(dut, 20000, 2482, 0.0)


@cocotb.test()
async def test_axi_to_eth_clocks(dut) -> None:
    await run(dut, 4000, 2482, 0.3)


@cocotb.test()
async def test_eth_to_axi_clocks(dut) -> None:
    await run(dut, 2482, 4000, 0.3)
