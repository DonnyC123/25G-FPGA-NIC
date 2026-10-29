import random
import unittest

from common.pkg.pcs_pkg import CTRL_SYNC, DATA_SYNC, PCS_PAYLOAD_BYTES, PCS_PAYLOAD_W

from tb_utils.net.pcs_blocks import PcsBlock
from tb_utils.net.scrambler import MASK, STATE_W, TAP, Scrambler


def random_blocks(count: int, seed: int) -> list[PcsBlock]:
    rng = random.Random(seed)
    return [
        PcsBlock(rng.choice((CTRL_SYNC, DATA_SYNC)), rng.randbytes(PCS_PAYLOAD_BYTES))
        for _ in range(count)
    ]


def reference_descramble(blocks: list[PcsBlock]) -> list[bytes]:
    window = MASK
    for i, block in enumerate(blocks):
        shift = STATE_W + i * PCS_PAYLOAD_W
        window |= int.from_bytes(block.payload, "little") << shift
    out = 0
    for i in range(len(blocks) * PCS_PAYLOAD_W):
        j = STATE_W + i
        taps = (window >> j) ^ (window >> (j - TAP)) ^ (window >> (j - STATE_W))
        out |= (taps & 1) << i
    data = out.to_bytes(len(blocks) * PCS_PAYLOAD_BYTES, "little")
    return [
        data[i : i + PCS_PAYLOAD_BYTES] for i in range(0, len(data), PCS_PAYLOAD_BYTES)
    ]


class ScramblerTest(unittest.TestCase):
    def test_round_trip(self) -> None:
        tx = Scrambler()
        rx = Scrambler()
        for block in random_blocks(100, 0):
            self.assertEqual(rx.descramble(tx.scramble(block)), block)

    def test_self_sync(self) -> None:
        blocks = random_blocks(100, 1)
        tx = Scrambler()
        rx = Scrambler(random.Random(2).getrandbits(STATE_W))
        out = [rx.descramble(tx.scramble(block)) for block in blocks]
        self.assertNotEqual(out[0], blocks[0])
        self.assertEqual(out[1:], blocks[1:])

    def test_matches_descrambler_formula(self) -> None:
        blocks = random_blocks(100, 3)
        tx = Scrambler()
        scrambled = [tx.scramble(block) for block in blocks]
        expected = [block.payload for block in blocks]
        self.assertEqual(reference_descramble(scrambled), expected)

    def test_sync_untouched(self) -> None:
        tx = Scrambler()
        for block in random_blocks(100, 4):
            self.assertEqual(tx.scramble(block).sync, block.sync)


if __name__ == "__main__":
    unittest.main()
