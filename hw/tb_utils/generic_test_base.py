from typing import Generic, TypeVar

from cocotb.triggers import ClockCycles, RisingEdge

from hw.tb_utils.abstract_transactions import AbstractTransaction
from hw.tb_utils.generic_driver import GenericDriver
from hw.tb_utils.generic_model import GenericModel
from hw.tb_utils.generic_monitor import GenericMonitor
from hw.tb_utils.generic_scoreboard import GenericScoreboard
from hw.tb_utils.generic_sequence import GenericSequence

DriverT = TypeVar("DriverT", bound=GenericDriver)
SequenceT = TypeVar("SequenceT", bound=GenericSequence)
MonitorT = TypeVar("MonitorT", bound=GenericMonitor)
ModelT = TypeVar("ModelT", bound=GenericModel)


class GenericTestBase(Generic[DriverT, SequenceT, MonitorT, ModelT]):
    idle_cycles = 4
    settle_cycles = 16

    def __init__(
        self,
        dut,
        *,
        driver: type[DriverT],
        sequence_item: type[AbstractTransaction],
        sequence: type[SequenceT],
        monitor: type[MonitorT],
        output_transaction: type[AbstractTransaction] | None = None,
        model: type[ModelT] = GenericModel,
    ) -> None:
        self.dut = dut
        self.driver = driver(dut, sequence_item)
        self.sequence = sequence(self.driver)
        self.monitor = monitor(dut, output_transaction)
        self.model = model()
        self.scoreboard = GenericScoreboard(self.monitor, self.model)
        self.sequence.add_subscriber(self.scoreboard)

    async def wait_for_driver_done(self) -> None:
        while self.driver.busy():
            await RisingEdge(self.driver.clk)
        await ClockCycles(self.monitor.clk, self.settle_cycles)

    def check(self) -> None:
        self.scoreboard.check()

    async def finish(self) -> None:
        await self.sequence.add_idle(self.idle_cycles)
        await self.wait_for_driver_done()
        self.check()
