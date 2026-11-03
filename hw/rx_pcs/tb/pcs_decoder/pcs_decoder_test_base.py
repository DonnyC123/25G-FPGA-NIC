from typing import Self

from hw.rx_pcs.tb.pcs_decoder.pcs_decoder_model import PcsDecoderModel, describe
from hw.rx_pcs.tb.pcs_decoder.pcs_decoder_monitor import PcsDecoderMonitor
from hw.rx_pcs.tb.pcs_decoder.pcs_decoder_sequence import PcsDecoderSequence
from hw.rx_pcs.tb.pcs_decoder.pcs_decoder_sequence_item import PcsDecoderSequenceItem
from hw.rx_pcs.tb.pcs_decoder.pcs_decoder_transaction import PcsDecoderTransaction
from hw.tb_utils.generic_driver import GenericDriver
from hw.tb_utils.generic_test_base import GenericTestBase
from hw.tb_utils.tb_common import initialize_tb


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
