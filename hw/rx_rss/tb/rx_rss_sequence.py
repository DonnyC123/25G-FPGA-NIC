from hw.rx_rss.tb.rx_rss_sequence_item import RetaWrite, RxRssSequenceItem
from hw.tb_utils.rx_eth_stream import RxEthStreamSequence


class RxRssSequence(RxEthStreamSequence):
    async def add_reta_write(self, addr: int, queue: int) -> None:
        write = RetaWrite(addr, queue)
        await self.notify_subscribers(write)
        await self.add_transaction(RxRssSequenceItem.from_reta_write(write))
