from typing import Self

from hw.rx_csum.tb.rx_csum_model import RxCsumModel
from hw.rx_csum.tb.rx_csum_transaction import RxCsumTransaction
from hw.tb_utils.generic_driver import GenericDriver
from hw.tb_utils.generic_test_base import GenericTestBase
from hw.tb_utils.rx_eth_stream import (
    RxEthOutMonitor,
    RxEthStreamItem,
    RxEthStreamSequence,
    describe,
)
from hw.tb_utils.tb_common import initialize_tb


class RxCsumTestBase(
    GenericTestBase[GenericDriver, RxEthStreamSequence, RxEthOutMonitor, RxCsumModel]
):
    def __init__(self, dut) -> None:
        super().__init__(
            dut,
            driver=GenericDriver,
            sequence_item=RxEthStreamItem,
            sequence=RxEthStreamSequence,
            monitor=RxEthOutMonitor,
            output_transaction=RxCsumTransaction,
            model=RxCsumModel,
        )

    @classmethod
    async def start(cls, dut) -> Self:
        await initialize_tb(dut)
        tb = cls(dut)
        await tb.sequence.add_idle()
        return tb

    def check(self) -> None:
        self.scoreboard.check(describe)
