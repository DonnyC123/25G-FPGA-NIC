from typing import Self

import cocotb
from cocotb.triggers import RisingEdge

from hw.tb_utils.axi_stream import (
    AXI_WORD_BYTES,
    AxiStreamDriver,
    AxiStreamItem,
    AxiStreamReadyDriver,
    AxiStreamSequence,
)
from hw.tb_utils.generic_model import GenericModel
from hw.tb_utils.generic_test_base import GenericTestBase
from hw.tb_utils.random_utils import random_frame
from hw.tb_utils.tb_common import initialize_tb
from hw.tb_utils.tx_eth_stream import TxEthStreamMonitor

CLK_PERIODS_PS = {"axi_clk": 4000, "eth_clk": 3102}


class TxFifoTestBase(
    GenericTestBase[
        AxiStreamDriver, AxiStreamSequence, TxEthStreamMonitor, GenericModel
    ]
):
    settle_cycles = 16

    def __init__(self, dut, ready_probability: float) -> None:
        super().__init__(
            dut,
            driver=AxiStreamDriver,
            sequence_item=AxiStreamItem,
            sequence=AxiStreamSequence,
            monitor=TxEthStreamMonitor,
        )
        self.ready_driver = AxiStreamReadyDriver(
            dut.tx_stream.ready, dut.eth_clk, ready_probability
        )
        self.max_frame = int(dut.FIFO_DEPTH.value) * AXI_WORD_BYTES - 1

    @classmethod
    async def start(cls, dut, ready_probability: float = 1.0) -> Self:
        await initialize_tb(dut, CLK_PERIODS_PS)
        return cls(dut, ready_probability)

    def random_frame(self, high: int) -> bytes:
        return random_frame(1, min(high, self.max_frame))

    async def wait_for_driver_done(self) -> None:
        await super().wait_for_driver_done()
        while self.dut.tx_stream.valid.value:
            await RisingEdge(self.dut.eth_clk)

    def check(self) -> None:
        self.scoreboard.check(bytes.hex)
        cocotb.log.info("delivered %d frames", len(self.monitor.items))
