from dataclasses import dataclass, field

from cocotb.types import Logic, LogicArray

from hw.common.pkg.parser_pkg import rx_parse_meta_t
from hw.tb_utils.rx_eth_stream import RxEthOutTransaction, RxEthOutWord


@dataclass
class RxParserTransaction(RxEthOutTransaction):
    meta_valid_o: Logic = field(default_factory=lambda: Logic(0))
    meta_o: LogicArray = field(
        default_factory=lambda: LogicArray.from_unsigned(0, rx_parse_meta_t.WIDTH)
    )

    @property
    def to_data(self) -> RxEthOutWord | None:
        return self.out_word(self.meta_valid_o, self.meta_o)
