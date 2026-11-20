from collections.abc import Iterable

import cocotb

from hw.common.pkg import pcs_pkg
from hw.tb_utils.generic_model import GenericModel
from hw.tb_utils.generic_scoreboard import check_stream
from hw.tb_utils.net.packets import add_fcs
from hw.tb_utils.net.pcs_blocks import PcsBlock, PcsEvent, decode, gaps


PAD_BYTES = pcs_pkg.ETH_MIN_FRAME_BYTES - pcs_pkg.ETH_FCS_BYTES


class TxFrameModel(GenericModel):
    def expected(self) -> list[bytes]:
        return [add_fcs(frame.ljust(PAD_BYTES, b"\0")) for frame in self.items]

    def check(self, blocks: Iterable[PcsBlock]) -> None:
        blocks = list(blocks)
        events = decode(blocks, check_preamble=True)
        errors = [event for event in events if event[0] != PcsEvent.FRAME]
        if errors:
            raise AssertionError(f"{len(errors)} block errors, first {errors[0]}")
        got = [data for _, data in events]
        check_stream(self.expected(), got, bytes.hex)
        short = [gap for gap in gaps(blocks) if gap < pcs_pkg.IPG_MIN]
        if short:
            raise AssertionError(f"{len(short)} gaps below {pcs_pkg.IPG_MIN}: {short[:8]}")
        cocotb.log.info("checked %d frames", len(got))
