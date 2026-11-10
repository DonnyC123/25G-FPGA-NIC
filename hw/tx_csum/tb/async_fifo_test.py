import random

import cocotb
from cocotb.triggers import ReadOnly, RisingEdge

from hw.tb_utils.tb_common import initialize_tb

COUNT = 2000
MAX_CYCLES = 100 * COUNT


async def writer(dut, values: list[int], probability: float) -> None:
    await RisingEdge(dut.axi_clk)
    i = 0
    while i < len(values):
        valid = random.random() < probability
        dut.valid_i.value = int(valid)
        dut.data_i.value = values[i]
        await ReadOnly()
        if valid and dut.ready_o.value:
            i += 1
        await RisingEdge(dut.axi_clk)
    dut.valid_i.value = 0


async def reader(dut, count: int, probability: float) -> list[int]:
    got: list[int] = []
    await RisingEdge(dut.eth_clk)
    for _ in range(MAX_CYCLES):
        if len(got) == count:
            break
        ready = random.random() < probability
        dut.ready_i.value = int(ready)
        await ReadOnly()
        if ready and dut.valid_o.value:
            got.append(int(dut.data_o.value))
        await RisingEdge(dut.eth_clk)
    dut.ready_i.value = 0
    if len(got) != count:
        raise AssertionError(f"read {len(got)} of {count} values in {MAX_CYCLES} cycles")
    return got


async def run(dut, periods: dict[str, int], write_probability: float, read_probability: float) -> None:
    dut.valid_i.value = 0
    dut.ready_i.value = 0
    await initialize_tb(dut, periods)
    width = len(dut.data_i)
    values = [random.getrandbits(width) for _ in range(COUNT)]
    cocotb.start_soon(writer(dut, values, write_probability))
    got = await reader(dut, COUNT, read_probability)
    for _ in range(20):
        await RisingEdge(dut.eth_clk)
    if dut.valid_o.value:
        raise AssertionError("valid_o still high after every value was read")
    if got != values:
        first = next(i for i, (a, b) in enumerate(zip(got, values)) if a != b)
        raise AssertionError(f"mismatch at {first}: got {got[first]:#x}, want {values[first]:#x}")


@cocotb.test()
async def test_fast_writer(dut) -> None:
    await run(dut, {"axi_clk": 3000, "eth_clk": 7100}, 0.9, 0.7)


@cocotb.test()
async def test_fast_reader(dut) -> None:
    await run(dut, {"axi_clk": 7100, "eth_clk": 3000}, 0.7, 0.9)


@cocotb.test()
async def test_full_and_empty(dut) -> None:
    await run(dut, {"axi_clk": 4000, "eth_clk": 3102}, 1.0, 0.1)


@cocotb.test()
async def test_trickle(dut) -> None:
    await run(dut, {"axi_clk": 4000, "eth_clk": 3102}, 0.1, 1.0)
