import random
import unittest
import zlib

from scapy.layers.inet import IP, TCP
from scapy.layers.inet6 import IPv6
from scapy.layers.l2 import Ether
from scapy.packet import Packet, Raw

from tb_utils.net.packets import ETH_MIN_LEN, FCS_LEN, frame_bytes, parse_frame

MAC_A = "02:00:00:00:00:01"
MAC_B = "02:00:00:00:00:02"
IP_HEADERS = {
    "ipv4": IP(src="10.0.0.1", dst="10.0.0.2"),
    "ipv6": IPv6(src="fe80::1", dst="fe80::2"),
}
CRC32_RESIDUE = 0x2144DF1C


def tcp_frame(ip: Packet, payload: bytes) -> Packet:
    return Ether(dst=MAC_B, src=MAC_A) / ip / TCP(sport=1234, dport=80) / payload


def tcp_payload(frame: Packet) -> bytes:
    return frame[Raw].load if Raw in frame else b""


class PacketsTest(unittest.TestCase):
    def test_round_trip(self) -> None:
        rng = random.Random(0)
        for name, ip in IP_HEADERS.items():
            for length in (0, 1, 5, 6, 7, 100, 1460):
                with self.subTest(name, length=length):
                    payload = rng.randbytes(length)
                    data = frame_bytes(tcp_frame(ip, payload))
                    back = parse_frame(data)
                    self.assertEqual(tcp_payload(back), payload)
                    self.assertEqual(frame_bytes(back), data)

    def test_min_size_padding(self) -> None:
        frame = tcp_frame(IP_HEADERS["ipv4"], b"")
        self.assertEqual(len(frame_bytes(frame, fcs=False)), ETH_MIN_LEN)
        self.assertEqual(len(frame_bytes(frame)), ETH_MIN_LEN + FCS_LEN)

    def test_fcs_residue(self) -> None:
        for name, ip in IP_HEADERS.items():
            with self.subTest(name):
                data = frame_bytes(tcp_frame(ip, b"hello"))
                self.assertEqual(zlib.crc32(data), CRC32_RESIDUE)

    def test_non_ip_payload(self) -> None:
        payload = bytes(range(60))
        frame = Ether(dst=MAC_B, src=MAC_A, type=0x88B5) / payload
        back = parse_frame(frame_bytes(frame))
        self.assertEqual(back.type, 0x88B5)
        self.assertEqual(back[Raw].load, payload)

    def test_bad_fcs_raises(self) -> None:
        data = bytearray(frame_bytes(tcp_frame(IP_HEADERS["ipv4"], b"hello")))
        data[20] ^= 1
        cases = {"corrupt byte": bytes(data), "too short": b"\x00\x01"}
        for name, bad in cases.items():
            with self.subTest(name), self.assertRaisesRegex(ValueError, "bad FCS"):
                parse_frame(bad)


if __name__ == "__main__":
    unittest.main()
