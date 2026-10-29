from dataclasses import dataclass, field

from cocotb.types import Logic

from tb_utils.abstract_transactions import AbstractTransaction


@dataclass
class AlignmentFinderTransaction(AbstractTransaction):
    aligned_o: Logic = field(default_factory=lambda: Logic(0))
    bitslip_o: Logic = field(default_factory=lambda: Logic(0))

    @property
    def to_data(self) -> tuple[bool, bool]:
        return bool(self.aligned_o), bool(self.bitslip_o)
