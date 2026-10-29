from dataclasses import dataclass

from tb_utils.generic_model import GenericModel


@dataclass
class SentFrame:
    data: bytes
    cancelled: bool = False


class RxFifoModel(GenericModel):
    def expected(self) -> list[bytes]:
        return [sent.data for sent in self.items if not sent.cancelled]
