from dataclasses import dataclass

from hw.common.pkg.csum_pkg import CSUM_W
from hw.common.pkg.tx_meta_pkg import TX_OFF_W

RESULT_FIELDS = [
    ("l4_en", 1),
    ("l4_pos", TX_OFF_W),
    ("l4_csum", CSUM_W),
]


@dataclass(frozen=True)
class CsumResult:
    l4_en: int = 0
    l4_pos: int = 0
    l4_csum: int = 0


def encode_result(result: CsumResult) -> int:
    value = 0
    for name, width in RESULT_FIELDS:
        value = (value << width) | (getattr(result, name) & ((1 << width) - 1))
    return value


def patch_frame(frame: bytes, result: CsumResult) -> bytes:
    out = bytearray(frame)
    if result.l4_en:
        for i, byte in ((result.l4_pos, result.l4_csum >> 8), (result.l4_pos + 1, result.l4_csum & 0xFF)):
            if i < len(out):
                out[i] = byte
    return bytes(out)
