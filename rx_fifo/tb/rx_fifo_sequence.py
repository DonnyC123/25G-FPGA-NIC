import random

from cocotb.types import Logic

from rx_fifo.tb.rx_fifo_driver import RxFifoEntry
from rx_fifo.tb.rx_fifo_model import SentFrame
from rx_fifo.tb.rx_fifo_sequence_item import WORD_BYTES, RxFifoSequenceItem
from tb_utils.generic_sequence import GenericSequence
from tb_utils.net.packets import split_words


class RxFifoSequence(GenericSequence[RxFifoEntry]):
    def __init__(self, driver) -> None:
        super().__init__(driver)
        self.gap_rate = 0.0

    async def add_word(
        self,
        word: bytes,
        sent: SentFrame | None = None,
        *,
        last: bool = False,
        drop: bool = False,
    ) -> None:
        item = RxFifoSequenceItem.from_bytes(word, last, drop)
        await self.add_transaction(RxFifoEntry(item, sent))

    async def add_frame(self, frame: bytes) -> None:
        sent = SentFrame(frame)
        await self.notify_subscribers(sent)
        words = split_words(frame, WORD_BYTES)
        if len(words[-1]) == WORD_BYTES:
            words.append(b"")
        for i, word in enumerate(words):
            if i and random.random() < self.gap_rate:
                await self.add_idle(random.randint(1, 3))
            await self.add_word(word, sent, last=i == len(words) - 1)

    async def add_dropped(self, frame: bytes, at: int, with_valid: bool) -> None:
        words = split_words(frame, WORD_BYTES)
        for word in words[:at]:
            await self.add_word(word)
        if with_valid:
            await self.add_word(words[at], drop=True)
        else:
            item = RxFifoSequenceItem(drop_i=Logic(1))
            await self.add_transaction(RxFifoEntry(item))
