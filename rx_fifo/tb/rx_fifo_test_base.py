from typing import Self

import cocotb
from cocotb.triggers import RisingEdge

from rx_fifo.tb.rx_fifo_driver import RxFifoDriver
from rx_fifo.tb.rx_fifo_model import RxFifoModel
from rx_fifo.tb.rx_fifo_sequence import RxFifoSequence
from rx_fifo.tb.rx_fifo_sequence_item import RxFifoSequenceItem
from tb_utils.axi_stream import AxiStreamMonitor, AxiStreamReadyDriver
from tb_utils.generic_test_base import GenericTestBase
from tb_utils.tb_common import initialize_tb

CLK_PERIODS_PS = {"eth_clk": 2482, "axi_clk": 4000}


class RxFifoTestBase(
    GenericTestBase[RxFifoDriver, RxFifoSequence, AxiStreamMonitor, RxFifoModel]
):
    settle_cycles = 8

    def __init__(self, dut, ready_probability: float) -> None:
        super().__init__(
            dut,
            driver=RxFifoDriver,
            sequence_item=RxFifoSequenceItem,
            sequence=RxFifoSequence,
            monitor=AxiStreamMonitor,
            model=RxFifoModel,
        )
        self.ready_driver = AxiStreamReadyDriver(
            dut.m_axi.ready, dut.axi_clk, ready_probability
        )

    @classmethod
    async def start(cls, dut, ready_probability: float = 1.0) -> Self:
        await initialize_tb(dut, CLK_PERIODS_PS)
        return cls(dut, ready_probability)

    async def wait_for_driver_done(self) -> None:
        await super().wait_for_driver_done()
        while self.dut.m_axi.valid.value:
            await RisingEdge(self.dut.axi_clk)

    def check(self) -> None:
        self.scoreboard.check(bytes.hex)
        cocotb.log.info(
            "delivered %d of %d frames, %d cancelled",
            len(self.monitor.items),
            len(self.model.items),
            self.driver.cancels,
        )
