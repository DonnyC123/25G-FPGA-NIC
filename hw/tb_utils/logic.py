from cocotb.types import LogicArray


def to_logic(data: bytes, width: int) -> LogicArray:
    return LogicArray.from_unsigned(int.from_bytes(data, "little"), width)


def from_logic(value: LogicArray, nbytes: int | None = None) -> bytes:
    data = int(value).to_bytes((len(value) + 7) // 8, "little")
    return data if nbytes is None else data[:nbytes]


def mask_of(nbytes: int, width: int) -> LogicArray:
    return LogicArray.from_unsigned((1 << nbytes) - 1, width)


def mask_len(mask: LogicArray) -> int:
    return int(mask).bit_length()
