import random
from collections.abc import Callable
from typing import NoReturn, Self

import cocotb
from cocotb.triggers import ReadOnly, RisingEdge

from hw.common.pkg import pcs_pkg
from hw.tb_utils.axi_stream import AxiStreamMonitor, AxiStreamReadyDriver
from hw.tb_utils.generic_model import GenericModel
from hw.tb_utils.generic_scoreboard import check_lossy_stream
from hw.tb_utils.generic_test_base import GenericTestBase
from hw.tb_utils.net.pcs_raw import PcsRawDriver, PcsRawItem, PcsRawSequence
from hw.tb_utils.tb_common import initialize_tb, reset_dut

CLK_PERIODS_PS = {"eth_clk": 2482, "axi_clk": 4000}
LOCK_CYCLES = 64
DRAIN_QUIET_CYCLES = 64
COUNTERS = ("overflow_drops_o", "crc_drops_o", "pcs_drops_o")


class RxTopDriver(PcsRawDriver):
    def __init__(self, dut, seq_item_type=None) -> None:
        super().__init__(dut, clk=dut.eth_clk)


class RxTopTestBase(
    GenericTestBase[RxTopDriver, PcsRawSequence, AxiStreamMonitor, GenericModel]
):
    idle_cycles = 8
    settle_cycles = 64

    def __init__(self, dut, ready_probability: float) -> None:
        super().__init__(
            dut,
            driver=RxTopDriver,
            sequence_item=PcsRawItem,
            sequence=PcsRawSequence,
            monitor=AxiStreamMonitor,
        )
        self.ready_driver = AxiStreamReadyDriver(
            dut.m_axi.ready, dut.axi_clk, ready_probability
        )
        self.lossless = ready_probability == 1.0
        self.exact_drops = True
        self.locked_cycles = 0
        self.base_drops = self.drops()
        cocotb.start_soon(self._track_lock())

    @classmethod
    async def start(cls, dut, ready_probability: float = 1.0) -> Self:
        await initialize_tb(dut, CLK_PERIODS_PS)
        tb = cls(dut, ready_probability)
        await tb.sequence.add_garbage(random.randrange(pcs_pkg.PCS_BLOCK_W))
        await tb.lock()
        await tb.wait_for_driver_done()
        tb.base_drops = tb.drops()
        return tb

    async def wait_for_driver_done(self) -> None:
        await super().wait_for_driver_done()
        quiet = 0
        while quiet < DRAIN_QUIET_CYCLES:
            await RisingEdge(self.dut.axi_clk)
            await ReadOnly()
            quiet = 0 if self.dut.m_axi.valid.value else quiet + 1
        await RisingEdge(self.dut.axi_clk)

    def drops(self) -> dict[str, int]:
        return {name: int(getattr(self.dut, name).value) for name in COUNTERS}

    async def _track_lock(self) -> NoReturn:
        while True:
            await RisingEdge(self.dut.eth_clk)
            await ReadOnly()
            if self.dut.locked_o.value != 1:
                self.locked_cycles = 0
            elif self.dut.raw_valid_i.value == 1:
                self.locked_cycles += 1

    async def _idle_while(self, condition: Callable[[], bool]) -> None:
        while condition():
            await self.sequence.add_idle(4)
            while self.driver.seq_item_queue.qsize() > 4:
                await RisingEdge(self.dut.eth_clk)

    async def lock(self) -> None:
        self.sequence.required = False
        await self._idle_while(lambda: self.locked_cycles < LOCK_CYCLES)
        self.sequence.required = self.lossless

    async def relock(self) -> None:
        self.exact_drops = False
        self.sequence.required = False
        await self._idle_while(lambda: self.locked_cycles > 0)
        await self.lock()

    async def reset(self) -> None:
        self.exact_drops = False
        await self.wait_for_driver_done()
        await reset_dut(self.dut)
        await self.lock()

    async def set_ready(self, probability: float) -> None:
        while self.driver.busy():
            await RisingEdge(self.dut.eth_clk)
        self.ready_driver.probability = probability
        self.lossless = probability == 1.0
        self.sequence.required = self.lossless

    def check(self) -> None:
        sent = self.model.items
        got = self.monitor.items
        dropped = check_lossy_stream(sent, got, bytes.hex)
        now = self.drops()
        overflow, crc, pcs = (now[name] - self.base_drops[name] for name in COUNTERS)
        cocotb.log.info(
            "delivered %d of %d frames; drops: overflow %d, crc %d, pcs %d",
            len(got),
            len(sent),
            overflow,
            crc,
            pcs,
        )
        if not self.exact_drops:
            return
        seq = self.sequence
        if overflow != dropped:
            raise AssertionError(f"{dropped} frames lost but {overflow} overflow drops")
        if crc + pcs != seq.bad_fcs + seq.corrupted or crc < seq.bad_fcs:
            raise AssertionError(
                f"sent {seq.bad_fcs} bad-FCS and {seq.corrupted} corrupted frames, "
                f"counted {crc} crc and {pcs} pcs drops"
            )
