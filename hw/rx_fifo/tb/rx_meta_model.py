import random

from hw.common.pkg.rx_meta_pkg import rx_meta_t

from hw.common.pkg import rx_meta_pkg as pkg

HASH_BYTES = pkg.RX_META_HASH_W // pkg.RX_META_BYTE_W
CSUM_BYTES = pkg.RX_META_CSUM_W // pkg.RX_META_BYTE_W


def pack_meta(meta: rx_meta_t) -> int:
    value = 0
    for name, width in rx_meta_t.WIDTHS:
        value = (value << width) | (getattr(meta, name) & ((1 << width) - 1))
    return value


def random_meta() -> rx_meta_t:
    return rx_meta_t.unpack(random.getrandbits(rx_meta_t.WIDTH))


def meta_beat(meta: rx_meta_t) -> bytes:
    beat = bytearray(pkg.RX_META_BYTES)
    hash_end = pkg.RX_META_HASH_OFF + HASH_BYTES
    csum_end = pkg.RX_META_CSUM_OFF + CSUM_BYTES
    beat[pkg.RX_META_HASH_OFF : hash_end] = meta.hash.to_bytes(HASH_BYTES, "little")
    beat[pkg.RX_META_CSUM_OFF : csum_end] = meta.csum.to_bytes(CSUM_BYTES, "big")
    beat[pkg.RX_META_TYPE_OFF] = meta.hash_type
    beat[pkg.RX_META_QUEUE_OFF] = meta.rx_queue
    return bytes(beat)
