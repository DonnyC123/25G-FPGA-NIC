import random
from dataclasses import dataclass, field
from typing import Self

from cocotb.types import Logic, LogicArray

from hw.common.pkg import parser_pkg, pcs_pkg
from hw.tb_utils.abstract_transactions import AbstractTransaction
from hw.tb_utils.logic import from_logic, to_logic

WORD_BYTES = pcs_pkg.ETH_DATA_BYTES
DATA_W = pcs_pkg.ETH_DATA_W


@dataclass(frozen=True)
class StreamWord:
    data: bytes | None
    last: bool = False


@dataclass(frozen=True)
class RetaWrite:
    addr: int
    queue: int


def word_data(data: LogicArray, last_bytes: LogicArray, last: bool) -> bytes:
    nbytes = WORD_BYTES
    if last:
        nbytes = int(last_bytes)
    return from_logic(data, nbytes)


@dataclass
class RxStreamSequenceItem(AbstractTransaction):
    data_i: LogicArray = field(default_factory=lambda: to_logic(b"", DATA_W))
    last_bytes_i: LogicArray = field(
        default_factory=lambda: LogicArray.from_unsigned(0, pcs_pkg.LAST_BYTES_W)
    )
    valid_i: Logic = field(default_factory=lambda: Logic(0))
    last_i: Logic = field(default_factory=lambda: Logic(0))
    drop_i: Logic = field(default_factory=lambda: Logic(0))

    @classmethod
    def from_word(cls, word: StreamWord) -> Self:
        data = word.data or b""
        last_bytes = len(data) if word.last else 0
        filler = random.randbytes(WORD_BYTES - len(data))
        return cls(
            to_logic(data + filler, DATA_W),
            LogicArray.from_unsigned(last_bytes, pcs_pkg.LAST_BYTES_W),
            Logic(word.data is not None),
            Logic(word.last),
        )

    @property
    def to_data(self) -> StreamWord:
        data = None
        if self.valid_i:
            data = word_data(self.data_i, self.last_bytes_i, bool(self.last_i))
        return StreamWord(data, bool(self.last_i))


@dataclass
class RxRssSequenceItem(RxStreamSequenceItem):
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
