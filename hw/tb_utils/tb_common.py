import random

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import ClockCycles, Timer

CLOCKS = ("clk", "axi_clk", "eth_clk")
RESETS = (("rst", 1), ("axi_rst", 1), ("eth_rst", 1))


def start_clock(clk, period_ps: int, phase_ps: int = 0) -> None:
    async def run() -> None:
        if phase_ps:
            await Timer(phase_ps, unit="ps")
        await Clock(clk, period_ps, unit="ps").start()

    cocotb.start_soon(run())


async def reset_dut(dut, cycles: int = 2) -> None:
    resets = [(getattr(dut, n), on) for n, on in RESETS if hasattr(dut, n)]
    if not resets:
        raise RuntimeError(f"no reset among {[n for n, _ in RESETS]}")
    for signal, on in resets:
        signal.value = on
    for name in CLOCKS:
        if hasattr(dut, name):
            await ClockCycles(getattr(dut, name), cycles)
    for signal, on in resets:
        signal.value = 1 - on


async def initialize_tb(dut, periods_ps: dict[str, int] | None = None) -> None:
    for name, period in (periods_ps or {"clk": 10_000}).items():
        phase = random.randrange(period) if periods_ps else 0
        start_clock(getattr(dut, name), period, phase)
    await reset_dut(dut)
