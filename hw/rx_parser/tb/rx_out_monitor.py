from typing import Any

from hw.common.pkg.parser_pkg import rss_meta_t, rx_parse_meta_t
from hw.rx_parser.tb.rss_model import from_rss_meta
from hw.rx_parser.tb.rx_out_transaction import OutWord
from hw.rx_parser.tb.rx_parser_model import from_meta
from hw.tb_utils.generic_monitor import GenericMonitor


class RxOutMonitor(GenericMonitor):
    def __init__(self, dut, output_transaction=None) -> None:
        self.partial = bytearray()
        super().__init__(dut, output_transaction)

    def decode(self, value: int) -> Any:
        return value

    async def process(self, data: OutWord) -> None:
        if data.data is not None:
            self.partial += data.data
        if not data.last and data.meta is None:
            return
        meta = None if data.meta is None else self.decode(data.meta)
        frame = bytes(self.partial) if data.last else None
        await super().process((frame, meta))
        if data.last:
            self.partial = bytearray()


class RxParserMonitor(RxOutMonitor):
    def decode(self, value: int) -> Any:
        return from_meta(rx_parse_meta_t.unpack(value))


class RxRssMonitor(RxOutMonitor):
    def decode(self, value: int) -> Any:
        return from_rss_meta(rss_meta_t.unpack(value))
