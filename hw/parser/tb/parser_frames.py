import random

from scapy.layers.inet import (
    IP,
    TCP,
    UDP,
    IPOption_EOL,
    IPOption_LSRR,
    IPOption_NOP,
    IPOption_Router_Alert,
    IPOption_RR,
    IPOption_SSRR,
    IPOption_Timestamp,
)
from scapy.layers.inet6 import (
    IPv6,
    IPv6ExtHdrDestOpt,
    IPv6ExtHdrFragment,
    IPv6ExtHdrHopByHop,
    IPv6ExtHdrRouting,
)
from scapy.layers.l2 import ARP, Dot1AD, Dot1Q, Ether
from scapy.packet import Packet, Raw

from hw.common.pkg.parser_pkg import (
    ETHERTYPE_IPV4,
    ETHERTYPE_IPV6,
    ETHERTYPE_QINQ,
    ETHERTYPE_VLAN,
    IP_PROTO_AH,
    IP_PROTO_DSTOPTS,
    IP_PROTO_FRAGMENT,
    IP_PROTO_HOPOPT,
    IP_PROTO_ROUTING,
    IP_PROTO_TCP,
    IP_PROTO_UDP,
    IPV4_OPT_EOL,
    IPV4_OPT_LSRR,
    IPV4_OPT_NOP,
    IPV4_OPT_SSRR,
)
from hw.tb_utils.net.packets import pad

TCP_OPTS = [("MSS", 1460), ("NOP", None), ("WScale", 7), ("SAckOK", b""), ("Timestamp", (1, 2))]
HOPS = ["10.0.0.1", "10.0.0.2", "10.0.0.3", "10.0.0.4"]


def ip_opts(options: list) -> Packet:
    return IP(src="192.0.2.1", dst="198.51.100.9", options=options)


OPTION_FRAMES = [
    Ether() / ip_opts([IPOption_LSRR(routers=HOPS[:1])]) / TCP(),
    Ether() / ip_opts([IPOption_LSRR(routers=HOPS)]) / TCP() / Raw(b"s" * 200),
    Ether() / ip_opts([IPOption_SSRR(routers=HOPS[:3])]) / UDP() / Raw(b"s" * 50),
    Ether() / ip_opts([IPOption_NOP(), IPOption_LSRR(routers=HOPS[:2])]) / TCP(options=TCP_OPTS),
    Ether() / ip_opts([IPOption_NOP()] * 3 + [IPOption_SSRR(routers=HOPS)]) / UDP(),
    Ether() / ip_opts([IPOption_RR(routers=HOPS[:2]), IPOption_LSRR(routers=HOPS[:2])]) / TCP(),
    Ether() / ip_opts([IPOption_Router_Alert()]) / UDP() / Raw(b"r" * 20),
    Ether() / ip_opts([IPOption_Timestamp(flg=0, timestamp=1)]) / TCP(),
    Ether() / ip_opts([IPOption_NOP(), IPOption_EOL()]) / TCP(),
    Ether() / Dot1Q() / ip_opts([IPOption_LSRR(routers=HOPS[:2])]) / UDP() / Raw(b"v" * 300),
    Ether() / ip_opts([IPOption_LSRR(routers=HOPS[:2]), IPOption_SSRR(routers=HOPS[:1])]) / TCP(),
    Ether() / ip_opts([IPOption_NOP()] * 20 + [IPOption_LSRR(routers=HOPS[:1])]) / TCP(),
]

# Scapy applies these source routes anyway; RFC 791 treats bytes after EOL as padding and a route whose
# pointer is past its end as finished, so the header destination is the final one.
SCAPY_DIFFERS_FRAMES = [
    Ether() / ip_opts([IPOption_EOL(), IPOption_LSRR(routers=HOPS[:1])]) / TCP(),
    Ether() / ip_opts([IPOption_LSRR(pointer=12, routers=HOPS[:2])]) / TCP(),
]

KNOWN_FRAMES = [
    Ether() / IP() / TCP(),
    Ether() / IP() / TCP(options=TCP_OPTS) / Raw(b"x" * 1400),
    Ether() / IP(options=[IPOption_NOP()] * 4) / TCP(),
    Ether() / IP(options=[IPOption_RR(routers=["1.2.3.4"] * 9)]) / TCP(options=TCP_OPTS),
    Ether() / IP() / UDP() / Raw(b"y" * 100),
    Ether() / IP(flags="MF") / TCP(),
    Ether() / IP(frag=10) / TCP(),
    Ether() / IP(flags="DF") / TCP(),
    Ether() / Dot1Q() / IP() / TCP(),
    Ether() / Dot1AD() / Dot1Q() / IP(options=[IPOption_NOP()] * 40) / TCP(options=TCP_OPTS),
    Ether() / IPv6() / TCP(),
    Ether() / IPv6() / TCP(options=TCP_OPTS) / Raw(b"z" * 1400),
    Ether() / IPv6() / UDP(),
    Ether() / IPv6() / IPv6ExtHdrHopByHop() / TCP(),
    Ether() / IPv6() / IPv6ExtHdrDestOpt() / IPv6ExtHdrRouting() / TCP(),
    Ether() / IPv6() / IPv6ExtHdrFragment(offset=0, m=0) / TCP(),
    Ether() / IPv6() / IPv6ExtHdrFragment(offset=0, m=1) / TCP(),
    Ether() / IPv6() / IPv6ExtHdrFragment(offset=5, m=0) / TCP(),
    Ether() / IPv6() / IPv6ExtHdrHopByHop() / IPv6ExtHdrDestOpt() / IPv6ExtHdrRouting() / TCP(),
    Ether() / Dot1Q() / Dot1Q() / IPv6() / IPv6ExtHdrHopByHop() / IPv6ExtHdrRouting() / TCP(options=TCP_OPTS),
    Ether() / ARP(),
    Ether() / IP() / UDP(),
    Ether() / IP() / UDP() / Raw(b"u" * 1400),
    Ether() / IP(options=[IPOption_NOP()] * 8) / UDP() / Raw(b"u" * 30),
    Ether() / IP() / UDP(len=50) / Raw(b"u" * 10),
    Ether() / IP(flags="MF") / UDP(),
    Ether() / Dot1AD() / Dot1Q() / IP() / UDP() / Raw(b"u" * 300),
    Ether() / IPv6() / UDP() / Raw(b"u" * 1000),
    Ether() / IPv6() / IPv6ExtHdrHopByHop() / UDP(),
    Ether() / IPv6() / IPv6ExtHdrFragment(offset=0, m=0) / UDP() / Raw(b"u" * 50),
    Ether() / IPv6() / IPv6ExtHdrDestOpt() / IPv6ExtHdrRouting() / UDP(),
    Ether() / IPv6() / UDP(len=9),
    Ether() / IP(len=26) / UDP(len=6),
    Ether() / IPv6(plen=4) / UDP(len=4),
    Ether() / IP(len=28) / UDP(),
    *OPTION_FRAMES,
    *SCAPY_DIFFERS_FRAMES,
]


def eth_header(vlans: int, ethertype: int) -> bytes:
    hdr = random.randbytes(12)
    for _ in range(vlans):
        hdr += random.choice([ETHERTYPE_VLAN, ETHERTYPE_QINQ]).to_bytes(2, "big") + random.randbytes(2)
    return hdr + ethertype.to_bytes(2, "big")


def tcp_header() -> bytes:
    doff = random.choice([5, 5, 8, 15, random.randint(0, 15)])
    hdr = bytearray(random.randbytes(max(20, doff * 4)))
    hdr[12] = (doff << 4) | (hdr[12] & 0xF)
    return bytes(hdr)


def udp_packet(payload: bytes) -> bytes:
    length = 8 + len(payload)
    length = random.choice([length, length, length, length + 1, max(0, length - 1), random.getrandbits(16)])
    return random.randbytes(4) + length.to_bytes(2, "big") + random.randbytes(2) + payload


def l4_bytes(proto: int) -> bytes:
    payload = random.randbytes(random.choice([0, 1, 7, 100, random.randint(0, 1400)]))
    if proto == IP_PROTO_TCP:
        return tcp_header() + payload
    if proto == IP_PROTO_UDP:
        return udp_packet(payload)
    return random.randbytes(8) + payload


def ext_header(proto: int, next_hdr: int) -> bytes:
    if proto == IP_PROTO_FRAGMENT:
        frag = random.choice([0, 0, 1, 0x0008, random.getrandbits(16)])
        return bytes([next_hdr, 0]) + frag.to_bytes(2, "big") + random.randbytes(4)
    ext_len = random.choice([0, 0, 1, 3, random.randint(0, 20)])
    size = (ext_len + 2) * 4 if proto == IP_PROTO_AH else (ext_len + 1) * 8
    return bytes([next_hdr, ext_len]) + random.randbytes(size - 2)


def random_option() -> bytes:
    match random.choice(["nops", "srr", "srr", "tlv", "eol", "bad"]):
        case "nops":
            return bytes([IPV4_OPT_NOP] * random.randint(1, 6))
        case "srr":
            hops = random.randint(0, 4)
            length = 3 + 4 * hops
            ptr = random.choice([4, 4, 4, length + 1, random.randint(0, 255)])
            opt_type = random.choice([IPV4_OPT_LSRR, IPV4_OPT_SSRR])
            return bytes([opt_type, length, ptr]) + random.randbytes(4 * hops)
        case "tlv":
            length = random.randint(2, 10)
            return bytes([random.choice([0x07, 0x44, 0x94, 0x82]), length]) + random.randbytes(length - 2)
        case "eol":
            return bytes([IPV4_OPT_EOL]) + random.randbytes(random.randint(0, 3))
        case _:
            return bytes([random.getrandbits(8), random.choice([0, 1, 41, random.getrandbits(8)])])


def random_options() -> bytes:
    opts = b"".join(random_option() for _ in range(random.randint(1, 5)))[:40]
    return opts + bytes((-len(opts)) % 4)


def ipv4_packet() -> bytes:
    proto = random.choice([IP_PROTO_TCP] * 3 + [IP_PROTO_UDP] * 3 + [1, random.getrandbits(8)])
    body = l4_bytes(proto)
    if random.random() < 0.4:
        opts = random_options()
        ihl = 5 + len(opts) // 4
        hdr = bytearray(random.randbytes(20) + opts)
    else:
        ihl = random.choice([5, 5, 6, 15, random.randint(0, 15)])
        hdr = bytearray(random.randbytes(max(20, ihl * 4)))
    hdr[0] = (random.choice([4, 4, 4, 6]) << 4) | ihl
    total = len(hdr) + len(body)
    total = random.choice([total, total, total, random.getrandbits(16), max(0, total - 10)])
    hdr[2:4] = total.to_bytes(2, "big")
    frag = random.choice([0, 0, 0x4000, 0x2000, 0x0001, random.getrandbits(16)])
    hdr[6:8] = frag.to_bytes(2, "big")
    hdr[9] = proto
    return bytes(hdr) + body


def ipv6_packet() -> bytes:
    exts = [
        random.choice([IP_PROTO_HOPOPT, IP_PROTO_ROUTING, IP_PROTO_FRAGMENT, IP_PROTO_AH, IP_PROTO_DSTOPTS])
        for _ in range(random.choice([0, 0, 1, 2, 3]))
    ]
    proto = random.choice([IP_PROTO_TCP] * 3 + [IP_PROTO_UDP] * 3 + [50, 59])
    chain = exts + [proto]
    body = b"".join(ext_header(chain[i], chain[i + 1]) for i in range(len(exts))) + l4_bytes(proto)
    hdr = bytearray(random.randbytes(40))
    hdr[0] = (random.choice([6, 6, 6, 4]) << 4) | (hdr[0] & 0xF)
    plen = random.choice([len(body), len(body), len(body), 0, random.getrandbits(16), max(0, len(body) - 20)])
    hdr[4:6] = plen.to_bytes(2, "big")
    hdr[6] = chain[0]
    return bytes(hdr) + body


def random_frame() -> bytes:
    vlans = random.choice([0, 0, 1, 2, 3])
    match random.choice(["v4", "v4", "v6", "v6", "other"]):
        case "v4":
            frame = eth_header(vlans, ETHERTYPE_IPV4) + ipv4_packet()
        case "v6":
            frame = eth_header(vlans, ETHERTYPE_IPV6) + ipv6_packet()
        case _:
            frame = eth_header(vlans, random.getrandbits(16)) + random.randbytes(random.randint(0, 200))
    frame = pad(frame)[:1514]
    if random.random() < 0.15:
        frame = frame[: random.randint(1, len(frame))]
    return frame
