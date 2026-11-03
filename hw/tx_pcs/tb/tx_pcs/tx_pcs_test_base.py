from typing import Self

from cocotb.triggers import ClockCycles, RisingEdge

from hw.tb_utils.generic_test_base import GenericTestBase
from hw.tb_utils.net.pcs_raw import PcsRawMonitor
from hw.tb_utils.net.tx_frame_model import TxFrameModel
from hw.tb_utils.tb_common import initialize_tb
from hw.tb_utils.tx_eth_stream import (
    TxEthStreamDriver,
    TxEthStreamItem,
    TxEthStreamSequence,
)

DRAIN_CYCLES = 10_000


class TxPcsTestBase(
    GenericTestBase[TxEthStreamDriver, TxEthStreamSequence, PcsRawMonitor, TxFrameModel]
):
    def __init__(self, dut) -> None:
        super().__init__(
            dut,
            driver=TxEthStreamDriver,
            sequence_item=TxEthStreamItem,
            sequence=TxEthStreamSequence,
            monitor=PcsRawMonitor,
            model=TxFrameModel,
        )
        self.model.min_frame_bytes = int(dut.MIN_FRAME_BYTES.value)

    @classmethod
    async def start(cls, dut) -> Self:
        await initialize_tb(dut)
        return cls(dut)

    async def wait_for_driver_done(self) -> None:
        while self.driver.busy():
            await RisingEdge(self.dut.clk)
        for _ in range(DRAIN_CYCLES):
            if self.monitor.terms >= len(self.model.items):
                break
            await RisingEdge(self.dut.clk)
        await ClockCycles(self.dut.clk, self.settle_cycles)

    def check(self) -> None:
        if self.monitor.bubbles:
            raise AssertionError(f"raw_valid_o dropped for {self.monitor.bubbles} cycles")
        self.model.check(self.monitor.blocks)
