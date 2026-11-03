from typing import Any


class Publisher:
    def __init__(self) -> None:
        self.subscribers: list[Any] = []

    def add_subscriber(self, *subscribers) -> None:
        self.subscribers.extend(subscribers)

    async def notify_subscribers(self, data: Any) -> None:
        for sub in self.subscribers:
            await (sub.notify(data) if hasattr(sub, "notify") else sub(data))
