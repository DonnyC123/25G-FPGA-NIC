import random

from common.pkg.pcs_pkg import PCS_BLOCK_W, PCS_SYNC_W
from rx_pcs.tb.alignment_finder.alignment_finder_sequence_item import (
    BAD_SYNCS,
    GOOD_SYNCS,
)
from tb_utils.generic_sequence import GenericSequence
from tb_utils.net.pma_gearbox import BitChunk


class AlignmentFinderSequence(GenericSequence[BitChunk]):
    def __init__(self, driver):
        super().__init__(driver)
        self.position = 0

    async def _push(self, value: int, width: int) -> bytes:
        data = value.to_bytes((width + 7) // 8, "little")
        await self.add_transaction(BitChunk(data, width))
        self.position += width
        return data

    async def add_garbage(self, width: int):
        if width:
            position = self.position
            await self._push(random.getrandbits(width), width)
            await self.notify_subscribers((position, None))

    async def add_block(self, sync: int):
        payload = random.getrandbits(PCS_BLOCK_W - PCS_SYNC_W)
        position = self.position
        block = await self._push((payload << PCS_SYNC_W) | sync, PCS_BLOCK_W)
        await self.notify_subscribers((position, block))

    async def add_good(self, count: int = 1):
        for _ in range(count):
            await self.add_block(random.choice(GOOD_SYNCS))

    async def add_bad(self, count: int = 1):
        for _ in range(count):
            await self.add_block(random.choice(BAD_SYNCS))

    async def add_window(self, length: int, bad_positions):
        bad_positions = set(bad_positions)
        for i in range(length):
            if i in bad_positions:
                await self.add_bad()
            else:
                await self.add_good()
