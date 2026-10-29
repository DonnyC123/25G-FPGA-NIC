from dataclasses import dataclass, field

from cocotb.types import Logic, LogicArray

from common.pkg import pcs_pkg
from rx_mac.tb.crc_checker.crc_checker_sequence_item import DATA_W, CrcWord, word_data
from tb_utils.abstract_transactions import AbstractTransaction
from tb_utils.logic import to_logic


@dataclass
class CrcCheckerTransaction(AbstractTransaction):
    data_i: LogicArray = field(default_factory=lambda: to_logic(b"", DATA_W))
    last_bytes_i: LogicArray = field(
        default_factory=lambda: LogicArray.from_unsigned(0, pcs_pkg.LAST_BYTES_W)
    )
    valid_i: Logic = field(default_factory=lambda: Logic(0))
    last_i: Logic = field(default_factory=lambda: Logic(0))
    drop_i: Logic = field(default_factory=lambda: Logic(0))
    drop_o: Logic = field(default_factory=lambda: Logic(0))

    @property
    def to_data(self) -> CrcWord | None:
        data = None
        if self.valid_i:
            data = word_data(self.data_i, self.last_bytes_i, bool(self.last_i))
        drop = bool(self.drop_i) or bool(self.drop_o)
        word = CrcWord(data, bool(self.last_i) and data is not None, drop)
        return word if word != CrcWord(None) else None
