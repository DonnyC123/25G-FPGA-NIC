import cocotb
from cocotb.triggers import ClockCycles, FallingEdge, RisingEdge

from hw.tb_utils.tb_common import initialize_tb

SYNC_CYCLES = 2


async def start(dut, *, reset_done: int = 1, locked: int = 0) -> None:
    dut.rx_reset_done_i.value = reset_done
    dut.locked_i.value = locked
    await initialize_tb(dut)


async def count_pulses(dut, cycles: int) -> int:
    pulses = 0
    previous = 0
    for _ in range(cycles):
        await FallingEdge(dut.clk)
        current = int(dut.rx_reset_o.value)
        pulses += current and not previous
        previous = current
    return pulses


def timeout(dut) -> int:
    return int(dut.TIMEOUT_CYCLES.value)


def pulse_width(dut) -> int:
    return int(dut.PULSE_CYCLES.value)


@cocotb.test()
async def test_quiet_while_locked(dut) -> None:
    await start(dut, locked=1)
    if await count_pulses(dut, 5 * timeout(dut)):
        raise AssertionError("pulsed while locked")


@cocotb.test()
async def test_pulses_after_timeout(dut) -> None:
    await start(dut, locked=1)
    await ClockCycles(dut.clk, SYNC_CYCLES + 2)
    dut.locked_i.value = 0
    await FallingEdge(dut.clk)
    if await count_pulses(dut, timeout(dut) - 2):
        raise AssertionError("pulsed before the timeout")
    if await count_pulses(dut, SYNC_CYCLES + 4) != 1:
        raise AssertionError("no pulse at the timeout")


@cocotb.test()
async def test_pulse_width(dut) -> None:
    await start(dut)
    await RisingEdge(dut.rx_reset_o)
    high = 0
    while True:
        await FallingEdge(dut.clk)
        if not dut.rx_reset_o.value:
            break
        high += 1
    if high != pulse_width(dut):
        raise AssertionError(f"pulse was {high} cycles, expected {pulse_width(dut)}")


@cocotb.test()
async def test_retries_until_locked(dut) -> None:
    await start(dut)
    if await count_pulses(dut, 3 * (timeout(dut) + pulse_width(dut))) < 2:
        raise AssertionError("did not retry")
    dut.locked_i.value = 1
    await ClockCycles(dut.clk, SYNC_CYCLES + pulse_width(dut) + 2)
    if await count_pulses(dut, 3 * timeout(dut)):
        raise AssertionError("pulsed after lock returned")


@cocotb.test()
async def test_lock_inside_timeout_cancels(dut) -> None:
    await start(dut, locked=1)
    for _ in range(5):
        dut.locked_i.value = 0
        await ClockCycles(dut.clk, timeout(dut) // 2)
        dut.locked_i.value = 1
        await ClockCycles(dut.clk, SYNC_CYCLES + 2)
    if await count_pulses(dut, timeout(dut)):
        raise AssertionError("pulsed for a short lock loss")


@cocotb.test()
async def test_waits_for_rx_reset_done(dut) -> None:
    await start(dut, reset_done=0)
    if await count_pulses(dut, 5 * timeout(dut)):
        raise AssertionError("pulsed while the GT RX reset was still running")
    dut.rx_reset_done_i.value = 1
    if await count_pulses(dut, timeout(dut) + SYNC_CYCLES + 4) != 1:
        raise AssertionError("no pulse after the GT RX reset finished")
