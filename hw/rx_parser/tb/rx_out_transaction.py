from dataclasses import dataclass, field

from cocotb.types import Logic, LogicArray

from hw.common.pkg import pcs_pkg
from hw.common.pkg.parser_pkg import rss_meta_t, rx_parse_meta_t
from hw.rx_parser.tb.rx_stream_sequence_item import DATA_W, word_data
from hw.tb_utils.abstract_transactions import AbstractTransaction
from hw.tb_utils.logic import to_logic


@dataclass(frozen=True)
class OutWord:
    data: bytes | None
    last: bool
    meta: int | None


def out_word(
    data: LogicArray,
    last_bytes: LogicArray,
    valid: Logic,
    last: Logic,
    meta_valid: Logic,
    meta: LogicArray,
) -> OutWord | None:
    words = None
    if valid:
        words = word_data(data, last_bytes, bool(last))
    value = int(meta) if meta_valid else None
    if words is None and value is None:
        return None
    return OutWord(words, bool(last) and words is not None, value)


@dataclass
class RxOutTransaction(AbstractTransaction):
    out_data_o: LogicArray = field(default_factory=lambda: to_logic(b"", DATA_W))
    out_last_bytes_o: LogicArray = field(
        default_factory=lambda: LogicArray.from_unsigned(0, pcs_pkg.LAST_BYTES_W)
    )
    out_valid_o: Logic = field(default_factory=lambda: Logic(0))
    out_last_o: Logic = field(default_factory=lambda: Logic(0))


@dataclass
class RxParserTransaction(RxOutTransaction):
    meta_valid_o: Logic = field(default_factory=lambda: Logic(0))
    meta_o: LogicArray = field(
        default_factory=lambda: LogicArray.from_unsigned(0, rx_parse_meta_t.WIDTH)
    )

    @property
    def to_data(self) -> OutWord | None:
        return out_word(
            self.out_data_o,
            self.out_last_bytes_o,
            self.out_valid_o,
            self.out_last_o,
            self.meta_valid_o,
            self.meta_o,
        )


@dataclass
class RxRssTransaction(RxOutTransaction):
    rss_valid_o: Logic = field(default_factory=lambda: Logic(0))
    rss_o: LogicArray = field(
        default_factory=lambda: LogicArray.from_unsigned(0, rss_meta_t.WIDTH)
    )

    @property
    def to_data(self) -> OutWord | None:
        return out_word(
            self.out_data_o,
            self.out_last_bytes_o,
            self.out_valid_o,
            self.out_last_o,
            self.rss_valid_o,
            self.rss_o,
        )
