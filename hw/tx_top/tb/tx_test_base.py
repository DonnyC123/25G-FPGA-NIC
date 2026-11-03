from typing import Self

from cocotb.triggers import ClockCycles, RisingEdge

from hw.tb_utils.axi_stream import (
    AXI_WORD_BYTES,
    AxiStreamDriver,
    AxiStreamItem,
    AxiStreamSequence,
)
from hw.tb_utils.generic_test_base import GenericTestBase
from hw.tb_utils.net.pcs_raw import PcsRawMonitor
from hw.tb_utils.net.tx_frame_model import TxFrameModel
from hw.tb_utils.random_utils import random_frame
from hw.tb_utils.tb_common import initialize_tb, reset_dut

CLK_PERIODS_PS = {"axi_clk": 4000, "eth_clk": 3102}
DRAIN_CYCLES = 20_000


class TxTopMonitor(PcsRawMonitor):
    def __init__(self, dut, output_transaction=None) -> None:
        super().__init__(dut, output_transaction, clk=dut.eth_clk, rst=dut.eth_rst)


class TxTestBase(
    GenericTestBase[AxiStreamDriver, AxiStreamSequence, TxTopMonitor, TxFrameModel]
):
    def __init__(self, dut) -> None:
        super().__init__(
            dut,
            driver=AxiStreamDriver,
            sequence_item=AxiStreamItem,
            sequence=AxiStreamSequence,
            monitor=TxTopMonitor,
            model=TxFrameModel,
        )
        self.model.min_frame_bytes = int(dut.MIN_FRAME_BYTES.value)
        self.max_frame = int(dut.FIFO_DEPTH.value) * AXI_WORD_BYTES - 1

    @classmethod
    async def start(cls, dut, periods_ps: dict[str, int] | None = None) -> Self:
        await initialize_tb(dut, periods_ps or CLK_PERIODS_PS)
        return cls(dut)

    def random_frame(self, high: int) -> bytes:
        return random_frame(1, min(high, self.max_frame))

    async def reset(self) -> None:
        await reset_dut(self.dut)

    async def wait_for_driver_done(self) -> None:
        while self.driver.busy():
            await RisingEdge(self.dut.axi_clk)
        for _ in range(DRAIN_CYCLES):
            if self.monitor.terms >= len(self.model.items):
                break
            await RisingEdge(self.dut.eth_clk)
        await ClockCycles(self.dut.eth_clk, self.settle_cycles)

    def check(self) -> None:
        if self.monitor.bubbles:
            raise AssertionError(f"raw_valid_o dropped for {self.monitor.bubbles} cycles")
        self.model.check(self.monitor.blocks)
