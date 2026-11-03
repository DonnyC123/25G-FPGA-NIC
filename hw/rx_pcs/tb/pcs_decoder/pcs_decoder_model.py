from hw.tb_utils.generic_model import GenericModel
from hw.tb_utils.net.pcs_blocks import PcsEvent, decode

Event = tuple[PcsEvent, bytes]


def event(kind: PcsEvent, data: bytes) -> Event:
    return kind, data if kind is PcsEvent.FRAME else b""


def describe(e: Event) -> str:
    kind, data = e
    return f"{kind.name} ({len(data)} bytes) {data.hex()}"


class PcsDecoderModel(GenericModel):
    def expected(self) -> list[Event]:
        return [event(kind, data) for kind, data in decode(self.items)]
