from dataclasses import dataclass, field
from typing import NoReturn

from cocotb.triggers import ReadOnly, RisingEdge

from rx_fifo.tb.rx_fifo_model import SentFrame
from rx_fifo.tb.rx_fifo_sequence_item import RxFifoSequenceItem
from tb_utils.abstract_transactions import AbstractTransaction
from tb_utils.generic_driver import GenericDriver, drive


@dataclass
class RxFifoEntry(AbstractTransaction):
    item: RxFifoSequenceItem = field(default_factory=RxFifoSequenceItem)
    sent: SentFrame | None = None

    @property
    def to_data(self) -> bytes:
        return self.item.to_data


class RxFifoDriver(GenericDriver[RxFifoEntry]):
    def __init__(self, dut, seq_item_type=None) -> None:
        self.cancels = 0
        super().__init__(dut, RxFifoEntry, clk=dut.eth_clk)

    async def driver_loop(self) -> NoReturn:
        while True:
            entry = self.next_item()
            item = entry.item
            if entry.sent is not None and entry.sent.cancelled:
                item = RxFifoSequenceItem()
            drive(self.dut, item)
            await ReadOnly()
            if self.dut.cancel_o.value and not item.drop_i:
                self.cancels += 1
                if entry.sent is not None:
                    entry.sent.cancelled = True
            await RisingEdge(self.clk)
