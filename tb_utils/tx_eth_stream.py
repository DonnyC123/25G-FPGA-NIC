import random
from dataclasses import dataclass, field
from typing import NoReturn, Self

from cocotb.triggers import ReadOnly, RisingEdge
from cocotb.types import Logic, LogicArray

from tb_utils.abstract_transactions import AbstractTransaction
from tb_utils.generic_driver import GenericDriver, drive
from tb_utils.generic_monitor import GenericMonitor
from tb_utils.generic_sequence import GenericSequence
from tb_utils.logic import from_logic, to_logic

DATA_W = 64
WORD_BYTES = DATA_W // 8
LAST_BYTES_W = (WORD_BYTES - 1).bit_length()


def frame_words(frame: bytes) -> list[bytes]:
    words = [frame[i : i + WORD_BYTES] for i in range(0, len(frame), WORD_BYTES)]
    if not words or len(words[-1]) == WORD_BYTES:
        words.append(b"")
    return words


@dataclass
class TxEthStreamItem(AbstractTransaction):
    data: LogicArray = field(default_factory=lambda: to_logic(b"", DATA_W))
    last_bytes: LogicArray = field(
        default_factory=lambda: LogicArray.from_unsigned(0, LAST_BYTES_W)
    )
    valid: Logic = field(default_factory=lambda: Logic(0))
    last: Logic = field(default_factory=lambda: Logic(0))

    @classmethod
    def from_bytes(cls, data: bytes, last: bool = False) -> Self:
        last_bytes = len(data) if last else 0
        filler = random.randbytes(WORD_BYTES - len(data))
        return cls(
            to_logic(data + filler, DATA_W),
            LogicArray.from_unsigned(last_bytes, LAST_BYTES_W),
            Logic(1),
            Logic(last),
        )

    @property
    def to_data(self) -> bytes:
        nbytes = WORD_BYTES
        if self.last:
            nbytes = int(self.last_bytes)
        return from_logic(self.data, nbytes)


class TxEthStreamDriver(GenericDriver[TxEthStreamItem]):
    def __init__(self, dut, seq_item_type=None, stream=None, clk=None) -> None:
        self.stream = dut.tx_stream_i if stream is None else stream
        super().__init__(dut, TxEthStreamItem, clk=clk)

    async def driver_loop(self) -> NoReturn:
        await RisingEdge(self.clk)
        while True:
            item = self.next_item()
            drive(self.stream, item)
            accepted = False
            while not accepted:
                await ReadOnly()
                accepted = not item.valid or bool(self.stream.ready.value)
                await RisingEdge(self.clk)


class TxEthStreamSequence(GenericSequence[TxEthStreamItem]):
    def __init__(self, driver) -> None:
        super().__init__(driver)
        self.gap_rate = 0.0

    async def add_word(self, word: bytes, last: bool = False) -> None:
        await self.add_transaction(TxEthStreamItem.from_bytes(word, last))

    async def add_frame(self, frame: bytes) -> None:
        await self.notify_subscribers(frame)
        words = frame_words(frame)
        for i, word in enumerate(words):
            if i and random.random() < self.gap_rate:
                await self.add_idle(random.randint(1, 3))
            await self.add_word(word, last=i == len(words) - 1)


class TxEthStreamMonitor(GenericMonitor):
    def __init__(self, dut, output_transaction=None, stream=None, clk=None) -> None:
        self.stream = dut.tx_stream if stream is None else stream
        super().__init__(dut, clk=dut.eth_clk if clk is None else clk)

    async def monitor_loop(self) -> NoReturn:
        word_bytes = len(self.stream.data) // 8
        frame = bytearray()
        while True:
            await RisingEdge(self.clk)
            await ReadOnly()
            if not (self.stream.valid.value and self.stream.ready.value):
                continue
            last = bool(self.stream.last.value)
            count = word_bytes
            if last:
                count = int(self.stream.last_bytes.value)
            frame += from_logic(self.stream.data.value, count)
            if last:
                await self.process(bytes(frame))
                frame = bytearray()
