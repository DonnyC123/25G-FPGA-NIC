from dataclasses import dataclass
from typing import Self

from hw.common.pkg import parser_pkg as pkg
from hw.common.pkg import tx_meta_pkg as meta_pkg

from hw.tb_utils.net.checksum import CSUM_MASK, fold, ones_sum

FIELDS = (
    ("csum_start", meta_pkg.TX_META_START_OFF),
    ("csum_offset", meta_pkg.TX_META_OFFSET_OFF),
    ("frame_len", meta_pkg.TX_META_LEN_OFF),
)
FIELD_BYTES = meta_pkg.TX_META_FIELD_W // 8
VLAN_TYPES = (pkg.ETHERTYPE_VLAN, pkg.ETHERTYPE_QINQ)
L4_CSUM_OFF = {pkg.IP_PROTO_TCP: 16, pkg.IP_PROTO_UDP: 6}


@dataclass(frozen=True)
class TxMeta:
    csum: bool = False
    csum_start: int = 0
    csum_offset: int = 0
    frame_len: int = 0

    @property
    def csum_pos(self) -> int:
        return self.csum_start + self.csum_offset

    def pack(self) -> bytes:
        out = bytearray(meta_pkg.TX_META_BYTES)
        out[meta_pkg.TX_META_FLAGS_OFF] = int(self.csum) << meta_pkg.TX_META_CSUM_BIT
        for name, off in FIELDS:
            out[off : off + FIELD_BYTES] = getattr(self, name).to_bytes(FIELD_BYTES, "little")
        return bytes(out)

    @classmethod
    def unpack(cls, data: bytes) -> Self:
        fields = {
            name: int.from_bytes(data[off : off + FIELD_BYTES], "little") for name, off in FIELDS
        }
        csum = bool(data[meta_pkg.TX_META_FLAGS_OFF] >> meta_pkg.TX_META_CSUM_BIT & 1)
        return cls(csum, **fields)


def offload_csum(frame: bytes, meta: TxMeta) -> int | None:
    if not meta.csum or meta.csum_pos + 2 > len(frame):
        return None
    csum = ~ones_sum(frame[meta.csum_start :]) & CSUM_MASK
    return csum or CSUM_MASK


def expected_offload(frame: bytes, meta: TxMeta) -> bytes:
    csum = offload_csum(frame, meta)
    if csum is None:
        return frame
    out = bytearray(frame)
    out[meta.csum_pos : meta.csum_pos + 2] = csum.to_bytes(2, "big")
    return bytes(out)


def seed(frame: bytes, meta: TxMeta) -> bytes:
    pos = meta.csum_pos
    target = ~int.from_bytes(frame[pos : pos + 2], "big") & CSUM_MASK
    out = bytearray(frame)
    out[pos : pos + 2] = b"\0\0"
    rest = ones_sum(bytes(out[meta.csum_start :]))
    out[pos : pos + 2] = fold(target + (~rest & CSUM_MASK)).to_bytes(2, "big")
    return bytes(out)


def l4_header(frame: bytes) -> tuple[int, int] | None:
    off = pkg.ETH_TYPE_OFF
    for _ in range(pkg.MAX_VLANS + 1):
        if off + pkg.ETHERTYPE_BYTES > len(frame):
            return None
        ethertype = int.from_bytes(frame[off : off + pkg.ETHERTYPE_BYTES], "big")
        if ethertype not in VLAN_TYPES:
            break
        off += pkg.VLAN_TAG_BYTES
    else:
        return None
    p = off + pkg.ETHERTYPE_BYTES
    if ethertype == pkg.ETHERTYPE_IPV4 and p + pkg.IPV4_PROTO_OFF < len(frame):
        ver, ihl = frame[p] >> 4, frame[p] & 0xF
        frag = int.from_bytes(frame[p + pkg.IPV4_FRAG_OFF : p + pkg.IPV4_FRAG_OFF + 2], "big")
        if ver != pkg.IPV4_VERSION or ihl < pkg.IPV4_MIN_IHL or frag & pkg.IPV4_FRAG_MASK:
            return None
        return frame[p + pkg.IPV4_PROTO_OFF], p + (ihl << pkg.IPV4_IHL_SHIFT)
    if ethertype == pkg.ETHERTYPE_IPV6 and p + pkg.IPV6_NH_OFF < len(frame):
        if frame[p] >> 4 != pkg.IPV6_VERSION:
            return None
        return frame[p + pkg.IPV6_NH_OFF], p + pkg.IPV6_HDR_BYTES
    return None


def linux_meta(frame: bytes) -> TxMeta:
    l4 = l4_header(frame)
    offset = L4_CSUM_OFF.get(l4[0]) if l4 else None
    if l4 is None or offset is None or l4[1] + offset + 2 > len(frame):
        return TxMeta(frame_len=len(frame))
    return TxMeta(True, l4[1], offset, len(frame))
