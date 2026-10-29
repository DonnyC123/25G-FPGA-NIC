import random
from collections.abc import Mapping
from typing import TypeVar

T = TypeVar("T")


def pick(weights: Mapping[T, float]) -> T:
    return random.choices(list(weights), weights=list(weights.values()))[0]


def random_frame(low: int, high: int) -> bytes:
    return random.randbytes(random.randint(low, high))
