import random

import cocotb

from hw.common.pkg import nic_regs_pkg as regs
from hw.nic_regs.tb.nic_regs_test_base import WORD_BYTES, NicRegsTestBase

KEY_OFFSETS = [regs.REG_RSS_KEY_OFF + WORD_BYTES * k for k in range(regs.RSS_KEY_WORDS)]
RETA_OFFSETS = [regs.REG_RETA_OFF + WORD_BYTES * k for k in range(regs.RETA_WORDS)]
UNMAPPED_OFFSETS = [0x004, 0x00C, 0x04C, 0x070, 0x100, 0xFFC]
SLOW_ETH_PERIOD_PS = 20000


async def write_everything(tb: NicRegsTestBase) -> None:
    for offset in KEY_OFFSETS + RETA_OFFSETS:
        await tb.write(offset, random.getrandbits(32))
    await tb.write(regs.REG_RSS_CTRL_OFF, 1 << regs.RSS_CTRL_UDP_PORTS_BIT)


@cocotb.test()
async def test_reset_values(dut) -> None:
    tb = await NicRegsTestBase.start(dut)
    await tb.check_all_reads()
    for offset in UNMAPPED_OFFSETS:
        await tb.check_read(offset)
    await tb.check_outputs()


@cocotb.test()
async def test_key_table_and_ctrl(dut) -> None:
    tb = await NicRegsTestBase.start(dut)
    await write_everything(tb)
    await tb.check_all_reads()
    await tb.check_outputs()


@cocotb.test()
async def test_partial_strobes(dut) -> None:
    tb = await NicRegsTestBase.start(dut)
    for _ in range(40):
        offset = random.choice(KEY_OFFSETS + RETA_OFFSETS + [regs.REG_RSS_CTRL_OFF])
        await tb.write(offset, random.getrandbits(32), random.getrandbits(4))
    await tb.check_all_reads()
    await tb.check_outputs()


@cocotb.test()
async def test_read_only_and_unmapped(dut) -> None:
    tb = await NicRegsTestBase.start(dut)
    await tb.write(regs.REG_VERSION_OFF, 0xDEADBEEF)
    for offset in UNMAPPED_OFFSETS:
        await tb.write(offset, random.getrandbits(32))
    await tb.check_all_reads()
    for offset in UNMAPPED_OFFSETS:
        await tb.check_read(offset)
    await tb.check_outputs()


@cocotb.test()
async def test_slow_eth_clock(dut) -> None:
    tb = await NicRegsTestBase.start(dut, eth_period_ps=SLOW_ETH_PERIOD_PS)
    for _ in range(3):
        await write_everything(tb)
    await tb.check_all_reads()
    await tb.check_outputs()


@cocotb.test()
async def test_random_backpressure(dut) -> None:
    tb = await NicRegsTestBase.start(dut)
    tb.axil.ready_probability = 0.3
    offsets = KEY_OFFSETS + RETA_OFFSETS + [regs.REG_RSS_CTRL_OFF, regs.REG_VERSION_OFF]
    for _ in range(100):
        offset = random.choice(offsets)
        if random.random() < 0.6:
            await tb.write(offset, random.getrandbits(32), random.getrandbits(4))
        else:
            await tb.check_read(offset)
    await tb.check_all_reads()
    await tb.check_outputs()
