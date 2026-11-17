CSUM_W = 16
CSUM_MASK = (1 << CSUM_W) - 1


def fold(total: int) -> int:
    while total >> CSUM_W:
        total = (total & CSUM_MASK) + (total >> CSUM_W)
    return total


def ones_sum(data: bytes) -> int:
    if len(data) % 2:
        data += b"\0"
    words = (int.from_bytes(data[i : i + 2], "big") for i in range(0, len(data), 2))
    return fold(sum(words))
