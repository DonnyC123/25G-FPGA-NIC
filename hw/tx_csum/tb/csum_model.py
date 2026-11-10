from dataclasses import dataclass

from hw.common.pkg.parser_pkg import (
    CSUM_W,
    ETHERTYPE_IPV4,
    IPV4_ADDR_BYTES,
    IPV4_CSUM_OFF,
    IPV6_ADDR_BYTES,
    OFF_W,
)
from hw.parser.tb.pkt_parser_test_base import ParseMeta, expected_meta

CSUM_MASK = (1 << CSUM_W) - 1

RESULT_FIELDS = [
    ("ip_en", 1),
    ("ip_pos", OFF_W),
    ("ip_csum", CSUM_W),
    ("l4_en", 1),
    ("l4_pos", OFF_W),
    ("l4_csum", CSUM_W),
]
RESULT_W = sum(width for _, width in RESULT_FIELDS)


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


def decode_result(value: int) -> CsumResult:
    fields = {}
    shift = RESULT_W
    for name, width in RESULT_FIELDS:
        shift -= width
        fields[name] = (value >> shift) & ((1 << width) - 1)
    return CsumResult(**fields)


def encode_result(result: CsumResult) -> int:
    value = 0
    for name, width in RESULT_FIELDS:
        value = (value << width) | (getattr(result, name) & ((1 << width) - 1))
    return value


def fold(total: int) -> int:
    while total >> CSUM_W:
        total = (total & CSUM_MASK) + (total >> CSUM_W)
    return total


def ones_sum(data: bytes) -> int:
    if len(data) % 2:
        data += b"\0"
    return fold(sum(int.from_bytes(data[i : i + 2], "big") for i in range(0, len(data), 2)))


def zero_field(data: bytes, off: int) -> bytes:
    out = bytearray(data)
    out[off : off + 2] = b"\0\0"
    return bytes(out)


def l4_sum(frame: bytes, meta: ParseMeta) -> int:
    addr_len = IPV6_ADDR_BYTES if meta.ip_v6 else IPV4_ADDR_BYTES
    segment = zero_field(frame[meta.l4_off : meta.l4_end], meta.csum_pos - meta.l4_off)
    pseudo = ones_sum(frame[meta.addr_off : meta.addr_off + addr_len]) + meta.l4_proto + meta.l4_end - meta.l4_off
    return fold(pseudo + ones_sum(segment))


def expected_csum(frame: bytes, ext_stages: int) -> CsumResult:
    meta = expected_meta(frame, ext_stages)
    n = len(frame)
    ip_en = meta.eth_ok and meta.ethertype == ETHERTYPE_IPV4 and meta.ip_ok and not meta.ip_v6 and n >= meta.l4_off
    ip_csum = 0
    if ip_en:
        header = zero_field(frame[meta.payload_off : meta.l4_off], IPV4_CSUM_OFF)
        ip_csum = ~ones_sum(header) & CSUM_MASK
    l4_en = (meta.tcp_ok or meta.udp_ok) and not meta.csum_skip and n >= meta.l4_end
    l4_csum = 0
    if l4_en:
        l4_csum = ~l4_sum(frame, meta) & CSUM_MASK
        if meta.udp_ok and l4_csum == 0:
            l4_csum = CSUM_MASK
    return CsumResult(
        int(ip_en), meta.payload_off + IPV4_CSUM_OFF, ip_csum, int(l4_en), meta.csum_pos, l4_csum
    )


def patch_frame(frame: bytes, result: CsumResult) -> bytes:
    out = bytearray(frame)
    for en, pos, csum in ((result.ip_en, result.ip_pos, result.ip_csum), (result.l4_en, result.l4_pos, result.l4_csum)):
        if not en:
            continue
        for i, byte in ((pos, csum >> 8), (pos + 1, csum & 0xFF)):
            if i < len(out):
                out[i] = byte
    return bytes(out)


def force_zero_csum(frame: bytes, ext_stages: int) -> bytes:
    meta = expected_meta(frame, ext_stages)
    last_pair = meta.l4_off + ((meta.l4_end - meta.l4_off) // 2 - 1) * 2
    out = bytearray(zero_field(frame, last_pair))
    word = CSUM_MASK - l4_sum(bytes(out), meta)
    out[last_pair : last_pair + 2] = word.to_bytes(2, "big")
    return bytes(out)
