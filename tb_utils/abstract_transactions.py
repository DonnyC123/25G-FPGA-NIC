from abc import ABC, abstractmethod
from dataclasses import dataclass
from typing import Any, Self


@dataclass
class AbstractTransaction(ABC):
    @classmethod
    def invalid_seq_item(cls) -> Self:
        return cls()

    @property
    @abstractmethod
    def to_data(self) -> Any:
        pass
