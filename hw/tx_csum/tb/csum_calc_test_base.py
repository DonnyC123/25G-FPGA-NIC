from typing import NoReturn, Self

import cocotb
from cocotb.triggers import ReadOnly, RisingEdge

from hw.tb_utils.axi_stream import (
    AxiStreamDriver,
    AxiStreamItem,
    AxiStreamReadyDriver,
    AxiStreamSequence,
)
from hw.tb_utils.generic_model import GenericModel
from hw.tb_utils.generic_monitor import GenericMonitor
from hw.tb_utils.generic_test_base import GenericTestBase
from hw.tb_utils.tb_common import initialize_tb
from hw.tx_csum.tb.csum_model import RESULT_W, decode_result, expected_csum

CLK_PERIODS_PS = {"axi_clk": 4000}


class CsumCalcModel(GenericModel):
    ext_stages = 0
    opt_stages = 0

    def process(self, data: bytes) -> None:
        self.items.append(expected_csum(data, self.ext_stages, self.opt_stages).normalized())


class CsumResultMonitor(GenericMonitor):
    def __init__(self, dut, output_transaction=None) -> None:
        super().__init__(dut, clk=dut.axi_clk)
        if len(dut.result_o) != RESULT_W:
            raise AssertionError(f"result_o is {len(dut.result_o)} bits, RESULT_FIELDS give {RESULT_W}")

    async def monitor_loop(self) -> NoReturn:
        while True:
            await RisingEdge(self.clk)
            await ReadOnly()
            if self.dut.result_valid_o.value:
                await self.process(decode_result(int(self.dut.result_o.value)).normalized())


class CsumCalcTestBase(GenericTestBase[AxiStreamDriver, AxiStreamSequence, CsumResultMonitor, CsumCalcModel]):
    settle_cycles = 24

    def __init__(self, dut, ready_probability: float) -> None:
        super().__init__(
            dut,
            driver=AxiStreamDriver,
            sequence_item=AxiStreamItem,
            sequence=AxiStreamSequence,
            monitor=CsumResultMonitor,
            model=CsumCalcModel,
        )
        self.model.ext_stages = int(dut.EXT_STAGES.value)
        self.model.opt_stages = int(dut.OPT_STAGES.value)
        self.ready_driver = AxiStreamReadyDriver(dut.m_axi.ready, dut.axi_clk, ready_probability)

    @classmethod
    async def start(cls, dut, ready_probability: float = 1.0) -> Self:
        await initialize_tb(dut, CLK_PERIODS_PS)
        return cls(dut, ready_probability)

    async def wait_for_driver_done(self) -> None:
        await super().wait_for_driver_done()
        while self.dut.m_axi.valid.value:
            await RisingEdge(self.dut.axi_clk)
        for _ in range(self.settle_cycles):
            await RisingEdge(self.dut.axi_clk)

    def check(self) -> None:
        self.scoreboard.check()
        ip = sum(1 for item in self.monitor.items if item[0])
        l4 = sum(1 for item in self.monitor.items if item[2])
        cocotb.log.info("checked %d frames: %d ip csums, %d l4 csums", len(self.monitor.items), ip, l4)
