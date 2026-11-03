from typing import Self

from hw.rx_mac.tb.crc_checker.crc_checker_model import CrcCheckerModel, describe
from hw.rx_mac.tb.crc_checker.crc_checker_monitor import CrcCheckerMonitor
from hw.rx_mac.tb.crc_checker.crc_checker_sequence import CrcCheckerSequence
from hw.rx_mac.tb.crc_checker.crc_checker_sequence_item import CrcCheckerSequenceItem
from hw.rx_mac.tb.crc_checker.crc_checker_transaction import CrcCheckerTransaction
from hw.tb_utils.generic_driver import GenericDriver
from hw.tb_utils.generic_test_base import GenericTestBase
from hw.tb_utils.tb_common import initialize_tb


class CrcCheckerTestBase(
    GenericTestBase[
        GenericDriver, CrcCheckerSequence, CrcCheckerMonitor, CrcCheckerModel
    ]
):
    def __init__(self, dut) -> None:
        super().__init__(
            dut,
            driver=GenericDriver,
            sequence_item=CrcCheckerSequenceItem,
            sequence=CrcCheckerSequence,
            monitor=CrcCheckerMonitor,
            output_transaction=CrcCheckerTransaction,
            model=CrcCheckerModel,
        )

    @classmethod
    async def start(cls, dut) -> Self:
        await initialize_tb(dut)
        tb = cls(dut)
        await tb.sequence.add_idle()
        return tb

    def check(self) -> None:
        self.scoreboard.check(describe)
