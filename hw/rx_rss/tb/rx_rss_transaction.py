from dataclasses import dataclass, field

from cocotb.types import Logic, LogicArray

from hw.common.pkg.parser_pkg import rss_meta_t
from hw.tb_utils.rx_eth_stream import RxEthOutTransaction, RxEthOutWord


@dataclass
class RxRssTransaction(RxEthOutTransaction):
    rss_valid_o: Logic = field(default_factory=lambda: Logic(0))
    rss_o: LogicArray = field(
        default_factory=lambda: LogicArray.from_unsigned(0, rss_meta_t.WIDTH)
    )

    @property
    def to_data(self) -> RxEthOutWord | None:
        return self.out_word(self.rss_valid_o, self.rss_o)
