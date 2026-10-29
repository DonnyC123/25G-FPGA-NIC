from typing import Self

from rx_pcs.tb.pcs_decoder.pcs_decoder_model import PcsDecoderModel, describe
from rx_pcs.tb.pcs_decoder.pcs_decoder_monitor import PcsDecoderMonitor
from rx_pcs.tb.pcs_decoder.pcs_decoder_sequence import PcsDecoderSequence
from rx_pcs.tb.pcs_decoder.pcs_decoder_sequence_item import PcsDecoderSequenceItem
from rx_pcs.tb.pcs_decoder.pcs_decoder_transaction import PcsDecoderTransaction
from tb_utils.generic_driver import GenericDriver
from tb_utils.generic_test_base import GenericTestBase
from tb_utils.tb_common import initialize_tb


class PcsDecoderTestBase(
    GenericTestBase[
        GenericDriver, PcsDecoderSequence, PcsDecoderMonitor, PcsDecoderModel
    ]
):
    def __init__(self, dut) -> None:
        super().__init__(
            dut,
            driver=GenericDriver,
            sequence_item=PcsDecoderSequenceItem,
            sequence=PcsDecoderSequence,
            monitor=PcsDecoderMonitor,
            output_transaction=PcsDecoderTransaction,
            model=PcsDecoderModel,
        )

    @classmethod
    async def start(cls, dut) -> Self:
        await initialize_tb(dut)
        return cls(dut)

    def check(self) -> None:
        self.scoreboard.check(describe)
