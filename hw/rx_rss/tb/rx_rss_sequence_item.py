from dataclasses import dataclass, field
from typing import Self

from cocotb.types import Logic, LogicArray

from hw.common.pkg import parser_pkg
from hw.tb_utils.rx_eth_stream import RxEthStreamItem


@dataclass(frozen=True)
class RetaWrite:
    addr: int
    queue: int


@dataclass
class RxRssSequenceItem(RxEthStreamItem):
    reta_we_i: Logic = field(default_factory=lambda: Logic(0))
    reta_addr_i: LogicArray = field(
        default_factory=lambda: LogicArray.from_unsigned(0, parser_pkg.RETA_ADDR_W)
    )
    reta_queue_i: LogicArray = field(
        default_factory=lambda: LogicArray.from_unsigned(0, parser_pkg.RSS_QUEUE_W)
    )

    @classmethod
    def from_reta_write(cls, write: RetaWrite) -> Self:
        return cls(
            reta_we_i=Logic(1),
            reta_addr_i=LogicArray.from_unsigned(write.addr, parser_pkg.RETA_ADDR_W),
            reta_queue_i=LogicArray.from_unsigned(write.queue, parser_pkg.RSS_QUEUE_W),
        )
