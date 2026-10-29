class BitQueue:
    def __init__(self):
        self._buf = bytearray()
        self._start = 0
        self._end = 0

    def __len__(self) -> int:
        return self._end - self._start

    def push(self, value: bytes, width: int):
        shift = self._end % 8
        chunk = (int.from_bytes(value, "little") & ((1 << width) - 1)) << shift
        data = chunk.to_bytes((shift + width + 7) // 8, "little")
        if shift:
            self._buf[-1] |= data[0]
            data = data[1:]
        self._buf.extend(data)
        self._end += width

    def peek(self, width: int) -> bytes:
        if width > len(self):
            raise IndexError(f"peek {width} bits, only {len(self)} available")
        first = self._start // 8
        last = (self._start + width + 7) // 8
        value = int.from_bytes(self._buf[first:last], "little") >> (self._start % 8)
        return (value & ((1 << width) - 1)).to_bytes((width + 7) // 8, "little")

    def pop(self, width: int) -> bytes:
        value = self.peek(width)
        self.discard(width)
        return value

    def discard(self, count: int):
        self._start += min(count, len(self))
        done = self._start // 8
        del self._buf[:done]
        self._start -= 8 * done
        self._end -= 8 * done
