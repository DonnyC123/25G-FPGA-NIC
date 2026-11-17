import random

from hw.rx_parser.tb.rx_stream_sequence_item import WORD_BYTES, RetaWrite, StreamWord
from hw.tb_utils.generic_sequence import GenericSequence
from hw.tb_utils.net.packets import split_words


class RxStreamSequence(GenericSequence):
    def __init__(self, driver) -> None:
        super().__init__(driver)
        self.bubble_rate = 0.0

    async def _add(self, word: StreamWord) -> None:
        await self.notify_subscribers(word)
        await self.add_transaction(self.driver.seq_item_type.from_word(word))

    async def add_frame(self, data: bytes) -> None:
        words = split_words(data, WORD_BYTES)
        if len(words[-1]) == WORD_BYTES:
            words.append(b"")
        for i, word in enumerate(words):
            while self.bubble_rate and random.random() < self.bubble_rate:
                await self.add_idle()
            await self._add(StreamWord(word, last=i == len(words) - 1))

    async def add_reta_write(self, addr: int, queue: int) -> None:
        write = RetaWrite(addr, queue)
        await self.notify_subscribers(write)
        await self.add_transaction(self.driver.seq_item_type.from_reta_write(write))
