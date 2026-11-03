from typing import Generic, TypeVar

from hw.tb_utils.abstract_transactions import AbstractTransaction
from hw.tb_utils.generic_driver import GenericDriver
from hw.tb_utils.publisher import Publisher

ItemT = TypeVar("ItemT", bound=AbstractTransaction)


class GenericSequence(Publisher, Generic[ItemT]):
    def __init__(self, driver: GenericDriver[ItemT]) -> None:
        super().__init__()
        self.driver = driver

    async def add_transaction(self, item: ItemT) -> None:
        await self.driver.send(item)

    async def add_idle(self, count: int = 1) -> None:
        for _ in range(count):
            await self.add_transaction(self.driver.idle_item())
