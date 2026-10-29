import random
import unittest
from collections.abc import Iterable

from common.pkg.pcs_pkg import (
    CTRL_SYMBOL_W,
    CTRL_SYNC,
    DATA_SYNC,
    IDLE_BLK,
    OS_SOF_L4,
    PCS_CTRL_DATA_SYMBOL_W,
)

from tb_utils.net.pcs_blocks import (
    IDLE_BLOCKS,
    TERM,
    PcsBlock,
    PcsEvent,
    ctrl_block,
    data_block,
    decode,
    encode,
    idle_block,
)

FRAME = PcsEvent.FRAME
DROP = PcsEvent.DROP
BAD_SYNC = PcsEvent.BAD_SYNC
BAD_DATA = PcsEvent.UNEXPECTED_DATA
BAD_TERM = PcsEvent.UNEXPECTED_TERM
BAD_CTRL = PcsEvent.BAD_CTRL
BAD_PREAMBLE = PcsEvent.BAD_PREAMBLE


def kinds(blocks: Iterable[PcsBlock | None]) -> list[PcsEvent]:
    return [kind for kind, _ in decode(blocks)]


def flip(block: PcsBlock, index: int) -> PcsBlock:
    payload = bytearray(block.payload)
    payload[index] ^= 1
    return PcsBlock(block.sync, bytes(payload))


class PcsBlocksTest(unittest.TestCase):
    def test_round_trip(self) -> None:
        rng = random.Random(0)
        for lane in (0, 4):
            for length in range(4 if lane else 0, 41):
                with self.subTest(lane=lane, length=length):
                    frame = rng.randbytes(length)
                    blocks = [idle_block(), *encode(frame, lane), idle_block()]
                    packed = [PcsBlock.from_bytes(b.to_bytes()) for b in blocks]
                    self.assertEqual(packed, blocks)
                    self.assertEqual(decode(packed), [(FRAME, frame)])
                    self.assertEqual(
                        decode(packed, check_preamble=True), [(FRAME, frame)]
                    )

    def test_back_to_back(self) -> None:
        rng = random.Random(1)
        frames = [rng.randbytes(rng.randint(4, 40)) for _ in range(20)]
        blocks = [b for i, f in enumerate(frames) for b in encode(f, 4 * (i % 2))]
        self.assertEqual(decode(blocks), [(FRAME, f) for f in frames])

    def test_layout(self) -> None:
        self.assertEqual(idle_block().to_bytes(), bytes([0x79]) + bytes(8))
        self.assertEqual(
            encode(b""),
            [
                PcsBlock(
                    CTRL_SYNC, bytes([0x78, 0x55, 0x55, 0x55, 0x55, 0x55, 0x55, 0xD5])
                ),
                PcsBlock(CTRL_SYNC, bytes([0x87]) + bytes(7)),
            ],
        )
        self.assertEqual(
            encode(bytes(range(1, 14)), 4),
            [
                PcsBlock(CTRL_SYNC, bytes([0x33, 0, 0, 0, 0, 0x55, 0x55, 0x55])),
                PcsBlock(DATA_SYNC, bytes([0x55, 0x55, 0x55, 0xD5, 1, 2, 3, 4])),
                PcsBlock(DATA_SYNC, bytes(range(5, 13))),
                PcsBlock(CTRL_SYNC, bytes([0x99, 13]) + bytes(6)),
            ],
        )

    def test_idle_blocks_ignored(self) -> None:
        self.assertEqual(decode([ctrl_block(t) for t in IDLE_BLOCKS]), [])

    def test_os_sof_l4_starts_frame(self) -> None:
        frame = bytes(range(20))
        blocks = encode(frame, 4)
        blocks[0] = ctrl_block(OS_SOF_L4, blocks[0].payload[1:])
        self.assertEqual(decode(blocks), [(FRAME, frame)])

    def test_bad_preamble(self) -> None:
        frame = bytes(range(16))
        cases = {
            "SOF_L0 preamble": (0, 0, 1),
            "SOF_L0 SFD": (0, 0, 7),
            "SOF_L4 ctrl preamble": (4, 0, 5),
            "SOF_L4 data preamble": (4, 1, 0),
            "SOF_L4 SFD": (4, 1, 3),
        }
        for name, (lane, block, index) in cases.items():
            with self.subTest(name):
                blocks = encode(frame, lane)
                blocks[block] = flip(blocks[block], index)
                self.assertEqual(
                    decode(blocks, check_preamble=True), [(BAD_PREAMBLE, frame)]
                )
                self.assertEqual(decode(blocks), [(FRAME, frame)])

    def test_bad_blocks(self) -> None:
        frame = bytes(range(16))
        opened = encode(frame)[:2]
        sof_l4 = encode(frame, 4)[:1]
        cases = {
            "bad sync outside frame": ([PcsBlock(0b00, bytes(8))], [BAD_SYNC]),
            "bad sync in frame": (
                [*opened, PcsBlock(0b11, bytes(8))],
                [BAD_SYNC, DROP],
            ),
            "data outside frame": ([data_block(bytes(8))], [BAD_DATA]),
            "term outside frame": ([ctrl_block(TERM[3])], [BAD_TERM]),
            "unknown type outside frame": ([ctrl_block(0x00)], [BAD_CTRL]),
            "idle in frame": ([*opened, idle_block()], [BAD_CTRL, DROP]),
            "unknown type in frame": ([*opened, ctrl_block(0x00)], [BAD_CTRL, DROP]),
            "start in frame": ([*opened, *encode(frame)], [BAD_CTRL, DROP, FRAME]),
            "idle after SOF_L4": ([*sof_l4, idle_block()], [BAD_CTRL, DROP]),
            "term after SOF_L4": ([*sof_l4, ctrl_block(TERM[3])], [BAD_CTRL, DROP]),
            "start after SOF_L4": ([*sof_l4, *encode(frame)], [BAD_CTRL, DROP, FRAME]),
        }
        for name, (blocks, expected) in cases.items():
            with self.subTest(name):
                self.assertEqual(kinds(blocks), expected)

    def test_lock_loss(self) -> None:
        frame = bytes(range(16))
        opened = encode(frame)[:2]
        sof_l4 = encode(frame, 4)[:1]
        cases = {
            "outside frame": ([None], []),
            "in frame": ([*opened, None], [DROP]),
            "after SOF_L4": ([*sof_l4, None], [DROP]),
            "after complete frame": ([*encode(frame), None], [FRAME]),
            "recovers": ([*opened, None, *encode(frame)], [DROP, FRAME]),
        }
        for name, (blocks, expected) in cases.items():
            with self.subTest(name):
                self.assertEqual(kinds(blocks), expected)

    def test_term_tail_codes(self) -> None:
        opened = encode(bytes(range(16)))[:2]
        for lane, term in enumerate(TERM[:-1]):
            first = CTRL_SYMBOL_W * (lane + 1)
            ones = ((1 << first) - 1).to_bytes(PCS_CTRL_DATA_SYMBOL_W, "little")
            tail = (1 << first).to_bytes(PCS_CTRL_DATA_SYMBOL_W, "little")
            with self.subTest(lane=lane):
                self.assertEqual(kinds([*opened, ctrl_block(term, ones)]), [FRAME])
                self.assertEqual(
                    kinds([*opened, ctrl_block(term, tail)]), [BAD_CTRL, DROP]
                )
                self.assertEqual(kinds([ctrl_block(term, tail)]), [BAD_CTRL])

    def test_idle_codes(self) -> None:
        for i in range(8):
            code = (1 << (CTRL_SYMBOL_W * i)).to_bytes(PCS_CTRL_DATA_SYMBOL_W, "little")
            with self.subTest(symbol=i):
                self.assertEqual(kinds([ctrl_block(IDLE_BLK, code)]), [BAD_CTRL])

    def test_drop_keeps_partial_bytes(self) -> None:
        frame = bytes(range(16))
        sof_l0_cut = [*encode(frame)[:2], idle_block()]
        sof_l4_cut = [*encode(frame, 4)[:3], idle_block()]
        self.assertEqual(decode(sof_l0_cut)[1], (DROP, frame[:8]))
        self.assertEqual(decode(sof_l4_cut)[1], (DROP, frame[:12]))


if __name__ == "__main__":
    unittest.main()
