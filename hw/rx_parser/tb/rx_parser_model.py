from dataclasses import dataclass

from hw.common.pkg import parser_pkg as pkg
from hw.common.pkg.parser_pkg import rx_parse_meta_t
from hw.tb_utils.generic_model import GenericModel
from hw.tb_utils.rx_eth_stream import frames

VLAN_TYPES = (pkg.ETHERTYPE_VLAN, pkg.ETHERTYPE_QINQ)
SKIP_PROTOS = (
    pkg.IP_PROTO_HOPOPT,
    pkg.IP_PROTO_ROUTING,
    pkg.IP_PROTO_DSTOPTS,
    pkg.IP_PROTO_AH,
)
PORT_PROTOS = (pkg.IP_PROTO_TCP, pkg.IP_PROTO_UDP)


@dataclass(frozen=True)
class ParseResult:
    ip_v4: bool = False
    ip_v6: bool = False
    src_addr: bytes = b""
    dst_addr: bytes = b""
    l4_proto: int | None = None
    ports: tuple[int, int] | None = None


def parse(stream: bytes) -> ParseResult:
    def has(i: int) -> bool:
        return i < len(stream)

    def be16(i: int) -> int:
        return int.from_bytes(stream[i : i + 2], "big")

    def ethertype_at(vlans: int) -> int:
        return be16(pkg.ETH_TYPE_OFF + pkg.VLAN_TAG_BYTES * vlans)

    vlans = 0
    while vlans < pkg.MAX_VLANS and ethertype_at(vlans) in VLAN_TYPES:
        vlans += 1
    ethertype = ethertype_at(vlans)
    ip = pkg.ETH_TYPE_OFF + pkg.ETHERTYPE_BYTES + pkg.VLAN_TAG_BYTES * vlans

    if ethertype == pkg.ETHERTYPE_IPV4:
        ver_ihl = stream[ip + pkg.IPV4_VER_IHL_OFF]
        ihl = ver_ihl & 0xF
        if ver_ihl >> 4 != pkg.IPV4_VERSION or ihl < pkg.IPV4_MIN_IHL:
            return ParseResult()
        addr = ip + pkg.IPV4_ADDR_OFF
        src = stream[addr : addr + pkg.IPV4_ADDR_LEN]
        dst = stream[addr + pkg.IPV4_ADDR_LEN : addr + 2 * pkg.IPV4_ADDR_LEN]
        proto = stream[ip + pkg.IPV4_PROTO_OFF]
        frag = (be16(ip + pkg.IPV4_FRAG_OFF) & pkg.IPV4_FRAG_MASK) != 0
        l4 = ip + (ihl << pkg.IPV4_IHL_SHIFT)
    elif ethertype == pkg.ETHERTYPE_IPV6:
        if stream[ip + pkg.IPV6_VER_OFF] >> 4 != pkg.IPV6_VERSION:
            return ParseResult()
        addr = ip + pkg.IPV6_ADDR_OFF
        src = stream[addr : addr + pkg.IPV6_ADDR_LEN]
        dst = stream[addr + pkg.IPV6_ADDR_LEN : addr + 2 * pkg.IPV6_ADDR_LEN]
        proto = stream[ip + pkg.IPV6_NH_OFF]
        l4 = ip + pkg.IPV6_HDR_BYTES
        while proto in SKIP_PROTOS and has(l4 + pkg.IPV6_EXT_LEN_OFF):
            ext_len = stream[l4 + pkg.IPV6_EXT_LEN_OFF]
            if proto == pkg.IP_PROTO_AH:
                size = (ext_len + 2) << pkg.IPV6_AH_SHIFT
            else:
                size = (ext_len + 1) << pkg.IPV6_EXT_SHIFT
            proto, l4 = stream[l4 + pkg.IPV6_EXT_NH_OFF], l4 + size
        frag = proto == pkg.IP_PROTO_FRAGMENT
    else:
        return ParseResult()

    ports = None
    if not frag and proto in PORT_PROTOS and has(l4 + pkg.PORTS_BYTES - 1):
        ports = (be16(l4 + pkg.L4_SRC_PORT_OFF), be16(l4 + pkg.L4_DST_PORT_OFF))
    return ParseResult(
        ethertype == pkg.ETHERTYPE_IPV4,
        ethertype == pkg.ETHERTYPE_IPV6,
        bytes(src),
        bytes(dst),
        proto,
        ports,
    )


def from_meta(meta: rx_parse_meta_t) -> ParseResult:
    ports = (meta.src_port, meta.dst_port) if meta.ports_valid else None
    if not (meta.ip_v4 or meta.ip_v6):
        return ParseResult(ports=ports)
    width = pkg.IPV6_ADDR_LEN if meta.ip_v6 else pkg.IPV4_ADDR_LEN
    mask = (1 << (8 * width)) - 1
    return ParseResult(
        bool(meta.ip_v4),
        bool(meta.ip_v6),
        (meta.src_addr & mask).to_bytes(width, "big"),
        (meta.dst_addr & mask).to_bytes(width, "big"),
        meta.l4_proto,
        ports,
    )


class RxParserModel(GenericModel):
    def expected(self) -> list[tuple]:
        return [(frame, parse(frame)) for frame in frames(self.items)]
