from typing import Any


class GenericModel:
    def __init__(self) -> None:
        self.items: list[Any] = []

    async def notify(self, data: Any) -> None:
        self.process(data)

    def process(self, data: Any) -> None:
        self.items.append(data)

    def expected(self) -> list[Any]:
        return self.items
