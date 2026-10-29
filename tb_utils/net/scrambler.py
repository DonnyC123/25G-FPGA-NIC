from tb_utils.net.pcs_blocks import PcsBlock

STATE_W = 58
TAP = 39
MASK = (1 << STATE_W) - 1


class Scrambler:
    def __init__(self, state: int = MASK) -> None:
        self.state = state

    def _run(self, payload: bytes, descramble: bool) -> bytes:
        data = int.from_bytes(payload, "little")
        state = self.state
        out = 0
        for i in range(len(payload) * 8):
            in_bit = (data >> i) & 1
            feedback = ((state >> (TAP - 1)) ^ (state >> (STATE_W - 1))) & 1
            out_bit = in_bit ^ feedback
            out |= out_bit << i
            scrambled_bit = in_bit if descramble else out_bit
            state = ((state << 1) | scrambled_bit) & MASK
        self.state = state
        return out.to_bytes(len(payload), "little")

    def scramble(self, block: PcsBlock) -> PcsBlock:
        return PcsBlock(block.sync, self._run(block.payload, False))

    def descramble(self, block: PcsBlock) -> PcsBlock:
        return PcsBlock(block.sync, self._run(block.payload, True))
