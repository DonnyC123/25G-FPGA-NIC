from hw.common.pkg.parser_pkg import rx_parse_meta_t
from hw.rx_parser.tb.rx_parser_model import ParseResult, from_meta
from hw.tb_utils.rx_eth_stream import RxEthOutMonitor


class RxParserMonitor(RxEthOutMonitor):
    def decode(self, value: int) -> ParseResult:
        return from_meta(rx_parse_meta_t.unpack(value))
