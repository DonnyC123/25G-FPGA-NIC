import struct

from scapy.layers.inet import IP
from scapy.layers.inet6 import IPv6
from scapy.layers.l2 import Ether

from hw.common.pkg import parser_pkg as pkg
from hw.tb_utils.generic_model import GenericModel
from hw.tb_utils.net.checksum import CSUM_MASK, ones_sum, ones_sum_fold
from hw.tb_utils.rx_eth_stream import frames


def expected_csum(frame: bytes) -> int:
    return ones_sum(frame[pkg.RX_CSUM_START : len(frame) - pkg.FCS_BYTES])


def csum_sub(total: int, value: int) -> int:
    return ones_sum_fold(total + (~value & CSUM_MASK))


def swap16(value: int) -> int:
    return ((value & 0xFF) << 8) | (value >> 8)


def linux_validates(frame: bytes, csum: int) -> bool:
    packet = Ether(frame[: len(frame) - pkg.FCS_BYTES])
    if IP in packet:
        ip = packet[IP]
        hdr_len = ip.ihl * 4
        ip_len = ip.len
        pseudo = bytes(ip)[12:20] + struct.pack(">BBH", 0, ip.proto, ip_len - hdr_len)
    elif IPv6 in packet:
        ip = packet[IPv6]
        hdr_len = pkg.IPV6_HDR_BYTES
        ip_len = pkg.IPV6_HDR_BYTES + ip.plen
        pseudo = bytes(ip)[8:40] + struct.pack(">IxxxB", ip.plen, ip.nh)
    else:
        return False
    data = frame[pkg.RX_CSUM_START : len(frame) - pkg.FCS_BYTES]
    ip_start = len(packet) - len(ip) - pkg.RX_CSUM_START
    total = csum_sub(csum, ones_sum(data[: ip_start + hdr_len]))
    pad = data[ip_start + ip_len :]
    pad_sum = ones_sum(pad)
    if (ip_start + ip_len) % 2:
        pad_sum = swap16(pad_sum)
    total = csum_sub(total, pad_sum)
    return ones_sum_fold(total + ones_sum(pseudo)) == CSUM_MASK


class RxCsumModel(GenericModel):
    def expected(self) -> list[tuple]:
        return [(frame, expected_csum(frame)) for frame in frames(self.items)]
