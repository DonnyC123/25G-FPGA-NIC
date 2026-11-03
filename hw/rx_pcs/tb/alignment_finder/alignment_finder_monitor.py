from collections import deque
from dataclasses import dataclass

from hw.common.pkg.pcs_pkg import PCS_SYNC_W
from hw.rx_pcs.tb.alignment_finder.alignment_finder_sequence_item import GOOD_SYNCS
from hw.rx_pcs.tb.alignment_finder.alignment_finder_transaction import (
    AlignmentFinderTransaction,
)
from hw.tb_utils.generic_monitor import GenericMonitor


@dataclass
class HeaderResult:
    position: int
    block: bytes
    good: bool
    aligned: bool
    bitslip: bool


class AlignmentFinderMonitor(GenericMonitor[AlignmentFinderTransaction]):
    def __init__(self, dut, output_transaction=None) -> None:
        self.driven: deque[tuple[int, bytes] | None] = deque()
        super().__init__(dut, output_transaction)

    async def on_driven(self, header: tuple[int, bytes] | None) -> None:
        self.driven.append(header)

    async def process(self, data: tuple[bool, bool]) -> None:
        header = self.driven.popleft()
        assert not self.driven, "driver sent two headers without an output sample"
        if header is None:
            return
        aligned, bitslip = data
        position, block = header
        good = (block[0] & ((1 << PCS_SYNC_W) - 1)) in GOOD_SYNCS
        await super().process(HeaderResult(position, block, good, aligned, bitslip))
