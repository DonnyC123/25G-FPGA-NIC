import random
import struct
import zlib

from scapy.layers.inet import IP, TCP
from scapy.layers.inet6 import IPv6
from scapy.layers.l2 import Ether
from scapy.packet import Packet, Raw

from hw.tb_utils.random_utils import random_frame

ETH_MIN_LEN = 60
ETH_MAX_LEN = 1518
FCS_LEN = 4


def pad(data: bytes) -> bytes:
    return data.ljust(ETH_MIN_LEN, b"\0")


def add_fcs(data: bytes) -> bytes:
    return data + struct.pack("<I", zlib.crc32(data))


def split_words(frame: bytes, size: int) -> list[bytes]:
    return [frame[i : i + size] for i in range(0, len(frame), size)]


def frame_bytes(packet: Packet, fcs: bool = True) -> bytes:
    data = pad(bytes(packet))
    return add_fcs(data) if fcs else data


def parse_frame(data: bytes, fcs: bool = True) -> Packet:
    if fcs:
        expected = struct.pack("<I", zlib.crc32(data[:-FCS_LEN]))
        if len(data) < FCS_LEN or expected != data[-FCS_LEN:]:
            raise ValueError("bad FCS")
        data = data[:-FCS_LEN]
    return Ether(data)


def random_ip_frame(ipv6: bool, fcs: bool = True) -> bytes:
    if ipv6:
        ip = IPv6(src="fe80::1", dst="fe80::2")
    else:
        ip = IP(src="10.0.0.1", dst="10.0.0.2")
    tcp = TCP(sport=random.randrange(1024, 65536), dport=80)
    payload = Raw(random_frame(0, 200))
    eth = Ether(src="02:00:00:00:00:01", dst="02:00:00:00:00:02")
    return frame_bytes(eth / ip / tcp / payload, fcs)
