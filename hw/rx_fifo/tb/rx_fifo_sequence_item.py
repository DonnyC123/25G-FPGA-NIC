from dataclasses import dataclass, field
from typing import Self

from cocotb.types import Logic, LogicArray

from hw.common.pkg import pcs_pkg
from hw.tb_utils.abstract_transactions import AbstractTransaction
from hw.tb_utils.logic import from_logic, to_logic

DATA_W = pcs_pkg.ETH_DATA_W
WORD_BYTES = pcs_pkg.ETH_DATA_BYTES


@dataclass
class RxFifoSequenceItem(AbstractTransaction):
    data_i: LogicArray = field(default_factory=lambda: to_logic(b"", DATA_W))
    last_bytes_i: LogicArray = field(
        default_factory=lambda: LogicArray.from_unsigned(0, pcs_pkg.LAST_BYTES_W)
    )
    valid_i: Logic = field(default_factory=lambda: Logic(0))
    last_i: Logic = field(default_factory=lambda: Logic(0))
    drop_i: Logic = field(default_factory=lambda: Logic(0))

    @classmethod
    def from_bytes(cls, data: bytes, last: bool = False, drop: bool = False) -> Self:
        last_bytes = len(data) if last else 0
        return cls(
            to_logic(data, DATA_W),
            LogicArray.from_unsigned(last_bytes, pcs_pkg.LAST_BYTES_W),
            Logic(1),
            Logic(last),
            Logic(drop),
        )

    @property
    def to_data(self) -> bytes:
        nbytes = WORD_BYTES
        if self.last_i:
            nbytes = int(self.last_bytes_i)
        return from_logic(self.data_i, nbytes)
