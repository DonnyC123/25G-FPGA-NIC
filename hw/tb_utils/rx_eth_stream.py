import random
from dataclasses import dataclass, field
from typing import Any, Self

from cocotb.types import Logic, LogicArray

from hw.tb_utils.abstract_transactions import AbstractTransaction
from hw.tb_utils.generic_monitor import GenericMonitor
from hw.tb_utils.generic_sequence import GenericSequence
from hw.tb_utils.logic import from_logic, to_logic
from hw.tb_utils.tx_eth_stream import DATA_W, LAST_BYTES_W, WORD_BYTES, frame_words


@dataclass(frozen=True)
class RxEthStreamWord:
    data: bytes | None
    last: bool = False


@dataclass(frozen=True)
class RxEthOutWord:
    data: bytes | None
    last: bool
    meta: int | None


def word_data(data: LogicArray, last_bytes: LogicArray, last: bool) -> bytes:
    nbytes = WORD_BYTES
    if last:
        nbytes = int(last_bytes)
    return from_logic(data, nbytes)


def frames(items: list) -> list:
    out: list = []
    frame = bytearray()
    for item in items:
        if not isinstance(item, RxEthStreamWord):
            out.append(item)
            continue
        if item.data is not None:
            frame += item.data
        if item.last:
            out.append(bytes(frame))
            frame = bytearray()
    return out


def describe(event: tuple) -> str:
    frame, result = event
    shown = "None" if frame is None else f"{len(frame)} bytes {frame[:64].hex()}"
    return f"frame {shown} -> {result}"


@dataclass
class RxEthStreamItem(AbstractTransaction):
    data_i: LogicArray = field(default_factory=lambda: to_logic(b"", DATA_W))
    last_bytes_i: LogicArray = field(
        default_factory=lambda: LogicArray.from_unsigned(0, LAST_BYTES_W)
    )
    valid_i: Logic = field(default_factory=lambda: Logic(0))
    last_i: Logic = field(default_factory=lambda: Logic(0))
    drop_i: Logic = field(default_factory=lambda: Logic(0))

    @classmethod
    def from_word(cls, word: RxEthStreamWord) -> Self:
        data = word.data or b""
        last_bytes = len(data) if word.last else 0
        filler = random.randbytes(WORD_BYTES - len(data))
        return cls(
            to_logic(data + filler, DATA_W),
            LogicArray.from_unsigned(last_bytes, LAST_BYTES_W),
            Logic(word.data is not None),
            Logic(word.last),
        )

    @property
    def to_data(self) -> RxEthStreamWord:
        data = None
        if self.valid_i:
            data = word_data(self.data_i, self.last_bytes_i, bool(self.last_i))
        return RxEthStreamWord(data, bool(self.last_i))


class RxEthStreamSequence(GenericSequence):
    def __init__(self, driver) -> None:
        super().__init__(driver)
        self.bubble_rate = 0.0

    async def add_word(self, word: RxEthStreamWord) -> None:
        await self.notify_subscribers(word)
        await self.add_transaction(self.driver.seq_item_type.from_word(word))

    async def add_frame(self, frame: bytes) -> None:
        words = frame_words(frame)
        for i, word in enumerate(words):
            while self.bubble_rate and random.random() < self.bubble_rate:
                await self.add_idle()
            await self.add_word(RxEthStreamWord(word, last=i == len(words) - 1))


@dataclass
class RxEthOutTransaction(AbstractTransaction):
    out_data_o: LogicArray = field(default_factory=lambda: to_logic(b"", DATA_W))
    out_last_bytes_o: LogicArray = field(
        default_factory=lambda: LogicArray.from_unsigned(0, LAST_BYTES_W)
    )
    out_valid_o: Logic = field(default_factory=lambda: Logic(0))
    out_last_o: Logic = field(default_factory=lambda: Logic(0))

    def out_word(self, meta_valid: Logic, meta: LogicArray) -> RxEthOutWord | None:
        data = None
        last = bool(self.out_last_o)
        if self.out_valid_o:
            data = word_data(self.out_data_o, self.out_last_bytes_o, last)
        value = int(meta) if meta_valid else None
        if data is None and value is None:
            return None
        return RxEthOutWord(data, last and data is not None, value)


class RxEthOutMonitor(GenericMonitor):
    def __init__(self, dut, output_transaction=None) -> None:
        self.partial = bytearray()
        super().__init__(dut, output_transaction)

    def decode(self, value: int) -> Any:
        return value

    async def process(self, data: RxEthOutWord) -> None:
        if data.data is not None:
            self.partial += data.data
        if not data.last and data.meta is None:
            return
        meta = None if data.meta is None else self.decode(data.meta)
        frame = bytes(self.partial) if data.last else None
        await super().process((frame, meta))
        if data.last:
            self.partial = bytearray()
