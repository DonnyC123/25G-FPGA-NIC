from typing import Self

from hw.rx_parser.tb.rx_out_monitor import RxParserMonitor
from hw.rx_parser.tb.rx_out_transaction import RxParserTransaction
from hw.rx_parser.tb.rx_parser_model import RxParserModel, describe
from hw.rx_parser.tb.rx_stream_sequence import RxStreamSequence
from hw.rx_parser.tb.rx_stream_sequence_item import RxStreamSequenceItem
from hw.tb_utils.generic_driver import GenericDriver
from hw.tb_utils.generic_test_base import GenericTestBase
from hw.tb_utils.tb_common import initialize_tb


class RxParserTestBase(
    GenericTestBase[GenericDriver, RxStreamSequence, RxParserMonitor, RxParserModel]
):
    def __init__(self, dut) -> None:
        super().__init__(
            dut,
            driver=GenericDriver,
            sequence_item=RxStreamSequenceItem,
            sequence=RxStreamSequence,
            monitor=RxParserMonitor,
            output_transaction=RxParserTransaction,
            model=RxParserModel,
        )

    @classmethod
    async def start(cls, dut) -> Self:
        await initialize_tb(dut)
        tb = cls(dut)
        await tb.sequence.add_idle()
        return tb

    def check(self) -> None:
        self.scoreboard.check(describe)
