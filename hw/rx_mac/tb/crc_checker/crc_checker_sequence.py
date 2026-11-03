import random
from collections.abc import Iterable

from hw.rx_mac.tb.crc_checker.crc_checker_sequence_item import (
    WORD_BYTES,
    CrcCheckerSequenceItem,
    CrcWord,
)
from hw.tb_utils.generic_sequence import GenericSequence
from hw.tb_utils.net.packets import split_words


class CrcCheckerSequence(GenericSequence[CrcCheckerSequenceItem]):
    def __init__(self, driver) -> None:
        super().__init__(driver)
        self.bubble_rate = 0.0

    async def _add(self, word: CrcWord) -> None:
        await self.notify_subscribers(word)
        await self.add_transaction(CrcCheckerSequenceItem.from_word(word))

    async def add_words(self, words: Iterable[bytes], *, last: bool = True) -> None:
        words = list(words)
        for i, word in enumerate(words):
            while self.bubble_rate and random.random() < self.bubble_rate:
                await self.add_idle()
            await self._add(CrcWord(word, last=last and i == len(words) - 1))

    async def add_frame(self, data: bytes) -> None:
        words = split_words(data, WORD_BYTES)
        if len(words[-1]) == WORD_BYTES:
            words.append(b"")
        await self.add_words(words)

    async def add_drop(self, word: bytes | None = None) -> None:
        await self._add(CrcWord(word, drop=True))
