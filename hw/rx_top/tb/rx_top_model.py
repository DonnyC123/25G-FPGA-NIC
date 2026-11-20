from hw.common.pkg import parser_pkg as parse_pkg
from hw.common.pkg import rx_meta_pkg as meta_pkg
from hw.common.pkg.rx_meta_pkg import rx_meta_t
from hw.rx_csum.tb.rx_csum_model import expected_csum
from hw.rx_fifo.tb.rx_meta_model import CSUM_BYTES, meta_beat
from hw.rx_parser.tb.rx_parser_model import VLAN_TYPES, parse
from hw.rx_rss.tb.rss_model import expected_rss

META_BYTES = meta_pkg.RX_META_BYTES


def be16(data: bytes, offset: int) -> int:
    return int.from_bytes(data[offset : offset + 2], "big")


def header_predictable(wire: bytes) -> bool:
    def type_off(vlans: int) -> int:
        return parse_pkg.ETH_TYPE_OFF + parse_pkg.VLAN_TAG_BYTES * vlans

    vlans = 0
    while vlans < parse_pkg.MAX_VLANS and be16(wire, type_off(vlans)) in VLAN_TYPES:
        vlans += 1
    ip = type_off(vlans) + parse_pkg.ETHERTYPE_BYTES
    ethertype = be16(wire, type_off(vlans))
    if ethertype == parse_pkg.ETHERTYPE_IPV4:
        return len(wire) >= ip + parse_pkg.IPV4_HDR_BYTES
    if ethertype == parse_pkg.ETHERTYPE_IPV6:
        return len(wire) >= ip + parse_pkg.IPV6_HDR_BYTES
    return True


def expected_meta(
    wire: bytes, key: bytes, udp_ports_en: bool, reta: list[int]
) -> rx_meta_t:
    rss = expected_rss(parse(wire), key, udp_ports_en, reta)
    return rx_meta_t(
        hash=rss.hash,
        csum=expected_csum(wire),
        hash_type=int(rss.hash_type),
        rx_queue=rss.rx_queue,
    )


def normalize(delivered: bytes) -> bytes:
    meta, wire = delivered[:META_BYTES], delivered[META_BYTES:]
    if header_predictable(wire):
        return delivered
    blanked = bytearray(META_BYTES)
    csum = slice(meta_pkg.RX_META_CSUM_OFF, meta_pkg.RX_META_CSUM_OFF + CSUM_BYTES)
    blanked[csum] = meta[csum]
    return bytes(blanked) + wire


def expected_delivery(
    wire: bytes, key: bytes, udp_ports_en: bool, reta: list[int]
) -> bytes:
    return normalize(meta_beat(expected_meta(wire, key, udp_ports_en, reta)) + wire)
