from typing import Self

from cocotb.triggers import ClockCycles, RisingEdge

from tb_utils.axi_stream import AxiStreamReadyDriver
from tb_utils.generic_test_base import GenericTestBase
from tb_utils.net.tx_frame_model import TxFrameModel
from tb_utils.tb_common import initialize_tb
from tb_utils.tx_eth_stream import (
    TxEthStreamDriver,
    TxEthStreamItem,
    TxEthStreamSequence,
)
from tx_mac.tb.tx_framer.tx_framer_monitor import TxFramerMonitor

DRAIN_CYCLES = 10_000


class TxFramerTestBase(
    GenericTestBase[
        TxEthStreamDriver, TxEthStreamSequence, TxFramerMonitor, TxFrameModel
    ]
):
    def __init__(self, dut, ready_probability: float) -> None:
        super().__init__(
            dut,
            driver=TxEthStreamDriver,
            sequence_item=TxEthStreamItem,
            sequence=TxEthStreamSequence,
            monitor=TxFramerMonitor,
            model=TxFrameModel,
        )
        self.model.min_frame_bytes = int(dut.MIN_FRAME_BYTES.value)
        self.ready_driver = AxiStreamReadyDriver(
            dut.out_ready_i, dut.clk, ready_probability
        )

    @classmethod
    async def start(cls, dut, ready_probability: float = 1.0) -> Self:
        await initialize_tb(dut)
        return cls(dut, ready_probability)

    async def wait_for_driver_done(self) -> None:
        while self.driver.busy():
            await RisingEdge(self.dut.clk)
        for _ in range(DRAIN_CYCLES):
            if self.monitor.terms >= len(self.model.items):
                break
            await RisingEdge(self.dut.clk)
        await ClockCycles(self.dut.clk, self.settle_cycles)

    def check(self) -> None:
        self.model.check(self.monitor.blocks)
