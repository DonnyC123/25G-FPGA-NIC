from collections.abc import Iterable
from dataclasses import dataclass
from enum import Enum, auto
from typing import Self

from common.pkg import pcs_pkg

TERM = (
    pcs_pkg.TERM_L0,
    pcs_pkg.TERM_L1,
    pcs_pkg.TERM_L2,
    pcs_pkg.TERM_L3,
    pcs_pkg.TERM_L4,
    pcs_pkg.TERM_L5,
    pcs_pkg.TERM_L6,
    pcs_pkg.TERM_L7,
)

START_BLOCKS = (pcs_pkg.SOF_L0, pcs_pkg.SOF_L4, pcs_pkg.OS_SOF_L4)
IDLE_BLOCKS = (pcs_pkg.IDLE_BLK, pcs_pkg.OS_OS, pcs_pkg.OS_L0, pcs_pkg.OS_L4)
PREAMBLE = bytes([0x55] * 6 + [0xD5])
BLOCK_BYTES = (pcs_pkg.PCS_BLOCK_W + 7) // 8
SOF_L4_LANE = 4


@dataclass(frozen=True)
class PcsBlock:
    sync: int
    payload: bytes

    def to_bytes(self) -> bytes:
        payload = int.from_bytes(self.payload, "little")
        value = self.sync | payload << pcs_pkg.PCS_SYNC_W
        return value.to_bytes(BLOCK_BYTES, "little")

    @classmethod
    def from_bytes(cls, value: bytes) -> Self:
        word = int.from_bytes(value, "little")
        sync = word & ((1 << pcs_pkg.PCS_SYNC_W) - 1)
        payload = (word >> pcs_pkg.PCS_SYNC_W) & ((1 << pcs_pkg.PCS_PAYLOAD_W) - 1)
        return cls(sync, payload.to_bytes(pcs_pkg.PCS_PAYLOAD_BYTES, "little"))


def ctrl_block(block_type: int, data: bytes = b"") -> PcsBlock:
    fields = data.ljust(pcs_pkg.PCS_CTRL_DATA_SYMBOL_W, b"\0")
    return PcsBlock(pcs_pkg.CTRL_SYNC, bytes([block_type]) + fields)


def data_block(data: bytes) -> PcsBlock:
    return PcsBlock(pcs_pkg.DATA_SYNC, data)


def idle_block() -> PcsBlock:
    return ctrl_block(pcs_pkg.IDLE_BLK)


def bad_tail(block: PcsBlock) -> PcsBlock:
    if block.payload[0] == pcs_pkg.TERM_L7:
        raise ValueError("TERM_L7 has no control tail")
    payload = bytearray(block.payload)
    payload[-1] |= 0x80
    return PcsBlock(block.sync, bytes(payload))


def encode(frame: bytes, sof_lane: int = 0) -> list[PcsBlock]:
    if sof_lane == 0:
        block_type = pcs_pkg.SOF_L0
    elif sof_lane == SOF_L4_LANE and len(frame) >= pcs_pkg.SOF_L4_PAYLOAD_BYTES:
        block_type = pcs_pkg.SOF_L4
    else:
        raise ValueError(f"cannot start {len(frame)} byte frame in lane {sof_lane}")
    data = bytes(sof_lane) + PREAMBLE + frame
    head = pcs_pkg.PCS_CTRL_DATA_SYMBOL_W
    blocks = [ctrl_block(block_type, data[:head])]
    data = data[head:]
    step = pcs_pkg.PCS_PAYLOAD_BYTES
    full = len(data) // step * step
    blocks += [data_block(data[i : i + step]) for i in range(0, full, step)]
    blocks.append(ctrl_block(TERM[len(data) - full], data[full:]))
    return blocks


class PcsEvent(Enum):
    FRAME = auto()
    DROP = auto()
    BAD_SYNC = auto()
    UNEXPECTED_DATA = auto()
    UNEXPECTED_TERM = auto()
    BAD_CTRL = auto()
    BAD_PREAMBLE = auto()


def ctrl_codes(block: PcsBlock) -> list[int]:
    fields = int.from_bytes(block.payload[1:], "little")
    mask = (1 << pcs_pkg.CTRL_SYMBOL_W) - 1
    return [
        (fields >> (pcs_pkg.CTRL_SYMBOL_W * i)) & mask
        for i in range(pcs_pkg.PCS_CTRL_SYMBOL_W)
    ]


def valid_ctrl(block: PcsBlock) -> bool:
    block_type = block.payload[0]
    if block_type == pcs_pkg.IDLE_BLK:
        first = 0
    elif block_type in TERM:
        first = TERM.index(block_type) + 1
    else:
        return True
    return all(code == pcs_pkg.CTRL_IDLE for code in ctrl_codes(block)[first:])


def block_error(block: PcsBlock, frame_open: bool) -> PcsEvent:
    if block.sync not in (pcs_pkg.CTRL_SYNC, pcs_pkg.DATA_SYNC):
        return PcsEvent.BAD_SYNC
    if block.sync == pcs_pkg.DATA_SYNC:
        return PcsEvent.UNEXPECTED_DATA
    if block.payload[0] in TERM and valid_ctrl(block) and not frame_open:
        return PcsEvent.UNEXPECTED_TERM
    return PcsEvent.BAD_CTRL


def decode(
    blocks: Iterable[PcsBlock | None], check_preamble: bool = False
) -> list[tuple[PcsEvent, bytes]]:
    events: list[tuple[PcsEvent, bytes]] = []
    frame: bytearray | None = None
    skip = 0
    for block in blocks:
        if block is None:
            if frame is not None:
                events.append((PcsEvent.DROP, bytes(frame[skip:])))
                frame = None
            continue
        block_type = block.payload[0] if valid_ctrl(block) else None
        is_ctrl = block.sync == pcs_pkg.CTRL_SYNC
        is_start = is_ctrl and block_type in START_BLOCKS
        if block.sync == pcs_pkg.DATA_SYNC and frame is not None:
            frame += block.payload
        elif (
            is_ctrl and block_type in TERM and frame is not None and len(frame) >= skip
        ):
            frame += block.payload[1 : 1 + TERM.index(block_type)]
            bad = check_preamble and frame[skip - len(PREAMBLE) : skip] != PREAMBLE
            kind = PcsEvent.BAD_PREAMBLE if bad else PcsEvent.FRAME
            events.append((kind, bytes(frame[skip:])))
            frame = None
        elif is_ctrl and block_type in IDLE_BLOCKS and frame is None:
            pass
        elif not (is_start and frame is None):
            events.append((block_error(block, frame is not None), block.payload))
            if frame is not None:
                events.append((PcsEvent.DROP, bytes(frame[skip:])))
                frame = None
        if is_start and frame is None:
            lane = 0 if block_type == pcs_pkg.SOF_L0 else SOF_L4_LANE
            frame = bytearray(block.payload[1:])
            skip = lane + len(PREAMBLE)
    return events


def corruptions(blocks: list[PcsBlock]) -> dict[str, list[PcsBlock]]:
    found = {
        "bad sync": [*blocks[:2], PcsBlock(0b11, bytes(8)), *blocks[2:]],
        "idle mid-frame": [*blocks[:2], idle_block(), *blocks[2:]],
        "truncated": blocks[:-1],
    }
    if blocks[-1].payload[0] != pcs_pkg.TERM_L7:
        found["bad term tail"] = [*blocks[:-1], bad_tail(blocks[-1])]
    return found


def gaps(blocks: Iterable[PcsBlock]) -> list[int]:
    found: list[int] = []
    idle: int | None = None
    for block in blocks:
        kind = block.payload[0] if block.sync == pcs_pkg.CTRL_SYNC else None
        if kind in TERM:
            idle = pcs_pkg.PCS_CTRL_DATA_SYMBOL_W - TERM.index(kind)
        elif kind == pcs_pkg.IDLE_BLK and idle is not None:
            idle += pcs_pkg.PCS_PAYLOAD_BYTES
        elif kind == pcs_pkg.SOF_L0 and idle is not None:
            found.append(idle)
            idle = None
    return found
