import zlib
from enum import Enum, auto

from hw.rx_mac.tb.crc_checker.crc_checker_sequence_item import CrcWord
from hw.tb_utils.generic_model import GenericModel

FCS_LEN = 4


class CrcEvent(Enum):
    SEND = auto()
    DROP = auto()


Event = tuple[CrcEvent, bytes]


def event(kind: CrcEvent, frame: bytes) -> Event:
    return kind, frame if kind is CrcEvent.SEND else b""


def describe(e: Event) -> str:
    kind, data = e
    return f"{kind.name} ({len(data)} bytes) {data.hex()}"


def fcs_ok(frame: bytes) -> bool:
    if len(frame) < FCS_LEN:
        return False
    body, fcs = frame[:-FCS_LEN], frame[-FCS_LEN:]
    return zlib.crc32(body).to_bytes(FCS_LEN, "little") == fcs


class CrcCheckerModel(GenericModel):
    def expected(self) -> list[Event]:
        events: list[Event] = []
        frame = bytearray()
        word: CrcWord
        for word in self.items:
            if word.drop:
                events.append(event(CrcEvent.DROP, b""))
                frame.clear()
            elif word.data is not None:
                frame += word.data
                if word.last:
                    kind = CrcEvent.SEND if fcs_ok(bytes(frame)) else CrcEvent.DROP
                    events.append(event(kind, bytes(frame)))
                    frame.clear()
        return events
