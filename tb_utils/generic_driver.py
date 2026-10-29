from dataclasses import fields, is_dataclass
from typing import Generic, NoReturn, TypeVar

from cocotb import start_soon
from cocotb.queue import Queue
from cocotb.triggers import RisingEdge

from tb_utils.abstract_transactions import AbstractTransaction

ItemT = TypeVar("ItemT", bound=AbstractTransaction)


def drive(handle, item) -> None:
    for f in fields(item):
        if not hasattr(handle, f.name):
            raise AttributeError(f"field '{f.name}' has no signal in '{handle._name}'")
        value = getattr(item, f.name)
        signal = getattr(handle, f.name)
        if is_dataclass(value):
            drive(signal, value)
        else:
            signal.value = value


class GenericDriver(Generic[ItemT]):
    def __init__(self, dut, seq_item_type: type[ItemT], clk=None) -> None:
        self.dut = dut
        self.seq_item_type = seq_item_type
        self.seq_item_queue: Queue[ItemT] = Queue()
        self.clk = dut.clk if clk is None else clk
        start_soon(self.driver_loop())

    async def send(self, item: ItemT) -> None:
        await self.seq_item_queue.put(item)

    def busy(self) -> bool:
        return not self.seq_item_queue.empty()

    def idle_item(self) -> ItemT:
        return self.seq_item_type.invalid_seq_item()

    def next_item(self) -> ItemT:
        if self.seq_item_queue.empty():
            return self.idle_item()
        return self.seq_item_queue.get_nowait()

    def drive_transaction(self, item: ItemT) -> None:
        drive(self.dut, item)

    async def driver_loop(self) -> NoReturn:
        while True:
            self.drive_transaction(self.next_item())
            await RisingEdge(self.clk)
