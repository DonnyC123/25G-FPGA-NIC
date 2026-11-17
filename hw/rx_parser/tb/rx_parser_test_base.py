from typing import Self

from hw.rx_parser.tb.rx_parser_model import RxParserModel
from hw.rx_parser.tb.rx_parser_monitor import RxParserMonitor
from hw.rx_parser.tb.rx_parser_transaction import RxParserTransaction
from hw.tb_utils.generic_driver import GenericDriver
from hw.tb_utils.generic_test_base import GenericTestBase
from hw.tb_utils.rx_eth_stream import RxEthStreamItem, RxEthStreamSequence, describe
from hw.tb_utils.tb_common import initialize_tb


class RxParserTestBase(
    GenericTestBase[GenericDriver, RxEthStreamSequence, RxParserMonitor, RxParserModel]
):
    def __init__(self, dut) -> None:
        super().__init__(
            dut,
            driver=GenericDriver,
            sequence_item=RxEthStreamItem,
            sequence=RxEthStreamSequence,
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
