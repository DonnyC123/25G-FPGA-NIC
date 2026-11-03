from dataclasses import dataclass, field
from typing import Self

from cocotb.types import Logic, LogicArray

from hw.common.pkg.pcs_pkg import CTRL_SYNC, DATA_SYNC, PCS_SYNC_W
from hw.tb_utils.abstract_transactions import AbstractTransaction

GOOD_SYNCS = (CTRL_SYNC, DATA_SYNC)
BAD_SYNCS = (0b00, 0b11)


@dataclass
class AlignmentFinderSequenceItem(AbstractTransaction):
    sync_valid_i: Logic = field(default_factory=lambda: Logic(0))
    sync_i: LogicArray = field(
        default_factory=lambda: LogicArray.from_unsigned(0, PCS_SYNC_W)
    )

    @classmethod
    def from_bytes(cls, block: bytes) -> Self:
        sync = block[0] & ((1 << PCS_SYNC_W) - 1)
        return cls(Logic(1), LogicArray.from_unsigned(sync, PCS_SYNC_W))

    @property
    def to_data(self) -> int:
        return int(self.sync_i)
