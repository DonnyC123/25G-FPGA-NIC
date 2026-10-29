from dataclasses import fields, is_dataclass
from typing import Any, Generic, NoReturn, TypeVar

from cocotb import start_soon
from cocotb.triggers import ReadOnly, RisingEdge

from tb_utils.abstract_transactions import AbstractTransaction
from tb_utils.publisher import Publisher

OutT = TypeVar("OutT", bound=AbstractTransaction)


def receive(handle, item) -> None:
    for f in fields(item):
        if not hasattr(handle, f.name):
            raise AttributeError(f"field '{f.name}' has no signal in '{handle._name}'")
        value = getattr(item, f.name)
        signal = getattr(handle, f.name)
        if is_dataclass(value):
            receive(signal, value)
        else:
            setattr(item, f.name, signal.value)


class GenericMonitor(Publisher, Generic[OutT]):
    def __init__(
        self, dut, output_transaction: type[OutT] | None = None, clk=None
    ) -> None:
        super().__init__()
        self.dut = dut
        self.output_transaction = output_transaction
        self.clk = dut.clk if clk is None else clk
        self.items: list[Any] = []
        start_soon(self.monitor_loop())

    async def sample(self) -> OutT:
        await RisingEdge(self.clk)
        await ReadOnly()
        if self.output_transaction is None:
            raise TypeError(f"{type(self).__name__} has no output_transaction")
        item = self.output_transaction()
        receive(self.dut, item)
        return item

    async def process(self, data: Any) -> None:
        self.items.append(data)
        await self.notify_subscribers(data)

    async def monitor_loop(self) -> NoReturn:
        while True:
            data = (await self.sample()).to_data
            if data is not None:
                await self.process(data)
