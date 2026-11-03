from hw.common.pkg.pcs_pkg import PCS_BLOCK_W
from hw.rx_pcs.tb.alignment_finder.alignment_finder_sequence_item import (
    AlignmentFinderSequenceItem,
)
from hw.tb_utils.net.pma_gearbox import GearboxDriver


class AlignmentFinderDriver(GearboxDriver):
    def __init__(
        self, dut, seq_item_type: type[AlignmentFinderSequenceItem]
    ) -> None:
        super().__init__(dut, seq_item_type, PCS_BLOCK_W)
