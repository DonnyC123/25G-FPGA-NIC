from dataclasses import dataclass, field

from cocotb.types import Logic, LogicArray

from hw.common.pkg.parser_pkg import CSUM_W
from hw.tb_utils.rx_eth_stream import RxEthOutTransaction, RxEthOutWord


@dataclass
class RxCsumTransaction(RxEthOutTransaction):
    csum_valid_o: Logic = field(default_factory=lambda: Logic(0))
    csum_o: LogicArray = field(
        default_factory=lambda: LogicArray.from_unsigned(0, CSUM_W)
    )

    @property
    def to_data(self) -> RxEthOutWord | None:
        return self.out_word(self.csum_valid_o, self.csum_o)
