import random
from collections.abc import Iterable

from rx_pcs.tb.pcs_decoder.pcs_decoder_sequence_item import PcsDecoderSequenceItem
from tb_utils.generic_sequence import GenericSequence
from tb_utils.net.pcs_blocks import PcsBlock, encode, idle_block


class PcsDecoderSequence(GenericSequence[PcsDecoderSequenceItem]):
    def __init__(self, driver) -> None:
        super().__init__(driver)
        self.bubble_rate = 0.0

    async def _add(self, block: PcsBlock, valid: bool, aligned: bool) -> None:
        if not aligned:
            await self.notify_subscribers(None)
        elif valid:
            await self.notify_subscribers(block)
        item = PcsDecoderSequenceItem.from_block(block, valid, aligned)
        await self.add_transaction(item)

    async def add_bubble(self, count: int = 1, *, aligned: bool = True) -> None:
        for _ in range(count):
            await self._add(idle_block(), valid=False, aligned=aligned)

    async def add_blocks(
        self, blocks: Iterable[PcsBlock], *, aligned: bool = True
    ) -> None:
        for block in blocks:
            while self.bubble_rate and random.random() < self.bubble_rate:
                await self.add_bubble(aligned=aligned)
            await self._add(block, valid=True, aligned=aligned)

    async def add_idle(self, count: int = 1, *, aligned: bool = True) -> None:
        await self.add_blocks([idle_block()] * count, aligned=aligned)

    async def add_frame(
        self, frame: bytes, sof_lane: int = 0, *, aligned: bool = True
    ) -> None:
        await self.add_blocks(encode(frame, sof_lane), aligned=aligned)
