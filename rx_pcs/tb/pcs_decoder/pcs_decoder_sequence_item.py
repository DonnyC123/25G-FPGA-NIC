from dataclasses import dataclass, field
from typing import Self

from cocotb.types import Logic, LogicArray

from common.pkg import pcs_pkg
from tb_utils.abstract_transactions import AbstractTransaction
from tb_utils.logic import from_logic, to_logic
from tb_utils.net.pcs_blocks import PcsBlock


@dataclass
class PcsDecoderSequenceItem(AbstractTransaction):
    pcs_block_i: LogicArray = field(
        default_factory=lambda: to_logic(b"", pcs_pkg.PCS_BLOCK_W)
    )
    valid_i: Logic = field(default_factory=lambda: Logic(0))
    aligned_i: Logic = field(default_factory=lambda: Logic(1))

    @classmethod
    def from_block(
        cls, block: PcsBlock, valid: bool = True, aligned: bool = True
    ) -> Self:
        return cls(
            to_logic(block.to_bytes(), pcs_pkg.PCS_BLOCK_W),
            Logic(valid),
            Logic(aligned),
        )

    @property
    def to_data(self) -> PcsBlock:
        return PcsBlock.from_bytes(from_logic(self.pcs_block_i))
