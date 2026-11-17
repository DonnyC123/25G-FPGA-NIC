from typing import Self

from cocotb.types import LogicArray

from hw.common.pkg import parser_pkg as pkg
from hw.rx_parser.tb.rss_model import DEFAULT_KEY, RxRssModel
from hw.rx_parser.tb.rx_out_monitor import RxRssMonitor
from hw.rx_parser.tb.rx_out_transaction import RxRssTransaction
from hw.rx_parser.tb.rx_parser_model import describe
from hw.rx_parser.tb.rx_stream_sequence import RxStreamSequence
from hw.rx_parser.tb.rx_stream_sequence_item import RxRssSequenceItem
from hw.tb_utils.generic_driver import GenericDriver
from hw.tb_utils.generic_test_base import GenericTestBase
from hw.tb_utils.tb_common import initialize_tb

DEFAULT_RETA = [i % pkg.RSS_MAX_QUEUES for i in range(pkg.RETA_SIZE)]


class RxRssTestBase(
    GenericTestBase[GenericDriver, RxStreamSequence, RxRssMonitor, RxRssModel]
):
    def __init__(self, dut) -> None:
        super().__init__(
            dut,
            driver=GenericDriver,
            sequence_item=RxRssSequenceItem,
            sequence=RxStreamSequence,
            monitor=RxRssMonitor,
            output_transaction=RxRssTransaction,
            model=RxRssModel,
        )

    @classmethod
    async def start(
        cls,
        dut,
        key: bytes = DEFAULT_KEY,
        udp_ports_en: bool = False,
        reta: list[int] | None = None,
    ) -> Self:
        await initialize_tb(dut)
        tb = cls(dut)
        tb.configure(key, udp_ports_en)
        await tb.sequence.add_idle()
        await tb.program_reta(DEFAULT_RETA if reta is None else reta)
        return tb

    def configure(self, key: bytes, udp_ports_en: bool) -> None:
        self.dut.rss_key_i.value = LogicArray.from_unsigned(
            int.from_bytes(key, "big"), pkg.RSS_KEY_W
        )
        self.dut.udp_ports_en_i.value = int(udp_ports_en)
        self.model.key = key
        self.model.udp_ports_en = udp_ports_en

    async def program_reta(self, reta: list[int]) -> None:
        for addr, queue in enumerate(reta):
            await self.sequence.add_reta_write(addr, queue)

    def check(self) -> None:
        self.scoreboard.check(describe)
