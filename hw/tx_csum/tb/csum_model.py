from dataclasses import dataclass

from hw.common.pkg.parser_pkg import CSUM_W, OFF_W

RESULT_FIELDS = [
    ("ip_en", 1),
    ("ip_pos", OFF_W),
    ("ip_csum", CSUM_W),
    ("l4_en", 1),
    ("l4_pos", OFF_W),
    ("l4_csum", CSUM_W),
]


@dataclass(frozen=True)
class CsumResult:
    ip_en: int = 0
    ip_pos: int = 0
    ip_csum: int = 0
    l4_en: int = 0
    l4_pos: int = 0
    l4_csum: int = 0

    def normalized(self) -> tuple:
        ip = (self.ip_pos, self.ip_csum) if self.ip_en else None
        l4 = (self.l4_pos, self.l4_csum) if self.l4_en else None
        return (self.ip_en, ip, self.l4_en, l4)


def encode_result(result: CsumResult) -> int:
    value = 0
    for name, width in RESULT_FIELDS:
        value = (value << width) | (getattr(result, name) & ((1 << width) - 1))
    return value


def patch_frame(frame: bytes, result: CsumResult) -> bytes:
    out = bytearray(frame)
    for en, pos, csum in ((result.ip_en, result.ip_pos, result.ip_csum), (result.l4_en, result.l4_pos, result.l4_csum)):
        if not en:
            continue
        for i, byte in ((pos, csum >> 8), (pos + 1, csum & 0xFF)):
            if i < len(out):
                out[i] = byte
    return bytes(out)
