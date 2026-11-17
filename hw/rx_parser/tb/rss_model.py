import ipaddress
import struct
from dataclasses import dataclass
from enum import IntEnum

from hw.common.pkg import parser_pkg as pkg
from hw.common.pkg.parser_pkg import rss_meta_t
from hw.rx_parser.tb.rx_parser_model import ParseResult, frames, parse
from hw.rx_parser.tb.rx_stream_sequence_item import RetaWrite
from hw.tb_utils.generic_model import GenericModel

DEFAULT_KEY = bytes.fromhex(
    "6d5a56da255b0ec24167253d43a38fb0d0ca2bcbae7b30b477cb2da38030f20c6a42b73bbeac01fa"
)

MS_VECTORS = [
    ("66.9.149.187", 2794, "161.142.100.80", 1766, 0x323E8FC2, 0x51CCC178),
    ("199.92.111.2", 14230, "65.69.140.83", 4739, 0xD718262A, 0xC626B0EA),
    ("24.19.198.95", 12898, "12.22.207.184", 38024, 0xD2D0A5DE, 0x5C2B394A),
    ("38.27.205.30", 48228, "209.142.163.6", 2217, 0x82989176, 0xAFC7327F),
    ("153.39.163.191", 44251, "202.188.127.2", 1303, 0x5D1809C5, 0x10E828A2),
    ("3ffe:2501:200:1fff::7", 2794, "3ffe:2501:200:3::1", 1766, 0x2CC18CD5, 0x40207D3D),
    ("3ffe:501:8::260:97ff:fe40:efab", 14230, "ff02::1", 4739, 0x0F0C461C, 0xDDE51BBF),
    (
        "3ffe:1900:4545:3:200:f8ff:fe21:67cf",
        44251,
        "fe80::200:f8ff:fe21:67cf",
        38024,
        0x4B61E985,
        0x02D1FEEF,
    ),
]


class HashType(IntEnum):
    NONE = 0
    L3 = 1
    L4 = 2


@dataclass(frozen=True)
class RssResult:
    hash_type: HashType
    hash: int
    rx_queue: int


def toeplitz(data: bytes, key: bytes) -> int:
    key_int = int.from_bytes(key, "big")
    key_w = 8 * len(key)
    result = 0
    for i in range(8 * len(data)):
        if (data[i // 8] >> (7 - i % 8)) & 1:
            window = key_int >> (key_w - pkg.RSS_HASH_W - i)
            result ^= window & ((1 << pkg.RSS_HASH_W) - 1)
    return result


def vector_input(
    src: str, dst: str, sport: int | None = None, dport: int | None = None
) -> bytes:
    data = ipaddress.ip_address(src).packed + ipaddress.ip_address(dst).packed
    if sport is not None and dport is not None:
        data += struct.pack(">HH", sport, dport)
    return data


def hash_input(result: ParseResult, udp_ports_en: bool) -> tuple[HashType, bytes]:
    if not (result.ip_v4 or result.ip_v6):
        return HashType.NONE, b""
    use_ports = result.ports is not None and (
        result.l4_proto == pkg.IP_PROTO_TCP
        or (result.l4_proto == pkg.IP_PROTO_UDP and udp_ports_en)
    )
    data = result.src_addr + result.dst_addr
    if use_ports and result.ports is not None:
        data += struct.pack(">HH", *result.ports)
        return HashType.L4, data
    return HashType.L3, data


def expected_rss(
    result: ParseResult, key: bytes, udp_ports_en: bool, reta: list[int]
) -> RssResult:
    hash_type, data = hash_input(result, udp_ports_en)
    if hash_type is HashType.NONE:
        return RssResult(HashType.NONE, 0, 0)
    value = toeplitz(data, key)
    return RssResult(hash_type, value, reta[value % pkg.RETA_SIZE])


def from_rss_meta(meta: rss_meta_t) -> RssResult:
    return RssResult(HashType(meta.hash_type), meta.hash, meta.rx_queue)


class RxRssModel(GenericModel):
    def __init__(self) -> None:
        super().__init__()
        self.key = DEFAULT_KEY
        self.udp_ports_en = False

    def expected(self) -> list[tuple]:
        reta = [0] * pkg.RETA_SIZE
        events: list[tuple] = []
        for item in frames(self.items):
            if isinstance(item, RetaWrite):
                reta[item.addr] = item.queue
                continue
            rss = expected_rss(parse(item), self.key, self.udp_ports_en, reta)
            events.append((item, rss))
        return events
