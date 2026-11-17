from hw.common.pkg.parser_pkg import rss_meta_t
from hw.rx_rss.tb.rss_model import RssResult, from_rss_meta
from hw.tb_utils.rx_eth_stream import RxEthOutMonitor


class RxRssMonitor(RxEthOutMonitor):
    def decode(self, value: int) -> RssResult:
        return from_rss_meta(rss_meta_t.unpack(value))
