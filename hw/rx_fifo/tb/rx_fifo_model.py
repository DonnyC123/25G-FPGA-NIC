from dataclasses import dataclass, field

from hw.common.pkg.rx_meta_pkg import rx_meta_t
from hw.rx_fifo.tb.rx_meta_model import meta_beat, pack_meta, random_meta
from hw.tb_utils.generic_model import GenericModel


@dataclass
class SentFrame:
    data: bytes
    cancelled: bool = False
    meta: rx_meta_t = field(default_factory=random_meta)

    @property
    def meta_value(self) -> int:
        return pack_meta(self.meta)


class RxFifoModel(GenericModel):
    def expected(self) -> list[bytes]:
        kept = [sent for sent in self.items if not sent.cancelled]
        return [meta_beat(sent.meta) + sent.data for sent in kept]
