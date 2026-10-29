import random
from collections import deque
from dataclasses import dataclass
from typing import NoReturn

from cocotb.triggers import FallingEdge, ReadOnly, RisingEdge

from tb_utils.abstract_transactions import AbstractTransaction
from tb_utils.bit_queue import BitQueue
from tb_utils.generic_driver import GenericDriver, drive
from tb_utils.publisher import Publisher


class PmaGearboxModel(BitQueue):
    def __init__(self, slip_latency: int = 1) -> None:
        super().__init__()
        self.position = 0
        self._slips = deque([False] * (slip_latency - 1))

    def request_slip(self, bitslip: bool) -> None:
        self._slips.append(bitslip)
        if self._slips.popleft():
            self.slip()

    def discard(self, count: int) -> None:
        count = min(count, len(self))
        super().discard(count)
        self.position += count

    def slip(self) -> None:
        if not len(self):
            raise IndexError("slip with no bits buffered")
        self.discard(1)


@dataclass
class BitChunk(AbstractTransaction):
    data: bytes = b""
    width: int = 0

    @property
    def to_data(self) -> tuple[bytes, int]:
        return self.data, self.width


class GearboxDriver(GenericDriver[BitChunk], Publisher):
    def __init__(
        self, dut, pin_item, width: int, slip_latency: int = 1, clk=None
    ) -> None:
        Publisher.__init__(self)
        self.pin_item = pin_item
        self.width = width
        self.gearbox = PmaGearboxModel(slip_latency)
        self.bubble_rate = 0.0
        super().__init__(dut, BitChunk, clk)

    def busy(self) -> bool:
        return super().busy() or len(self.gearbox) >= self.width

    def _fill(self) -> None:
        while len(self.gearbox) < 2 * self.width and not self.seq_item_queue.empty():
            self.gearbox.push(*self.seq_item_queue.get_nowait().to_data)

    async def driver_loop(self) -> NoReturn:
        drive(self.dut, self.pin_item.invalid_seq_item())
        while True:
            await FallingEdge(self.clk)
            self._fill()
            chunk, item = None, self.pin_item.invalid_seq_item()
            if (
                len(self.gearbox) >= self.width
                and random.random() >= self.bubble_rate
            ):
                chunk = (self.gearbox.position, self.gearbox.pop(self.width))
                item = self.pin_item.from_bytes(chunk[1])
            drive(self.dut, item)
            await self.notify_subscribers(chunk)
            await RisingEdge(self.clk)
            await ReadOnly()
            self.gearbox.request_slip(self.dut.bitslip_o.value == 1)
