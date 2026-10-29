from collections.abc import Callable, Sequence
from dataclasses import dataclass
from typing import Any

from tb_utils.generic_model import GenericModel
from tb_utils.generic_monitor import GenericMonitor


@dataclass(frozen=True)
class Expected:
    data: Any
    required: bool = True


def check_lossy_stream(
    expected: Sequence[Expected],
    got: Sequence[Any],
    describe: Callable[[Any], str] = repr,
) -> int:
    i = 0
    for n, have in enumerate(got):
        while i < len(expected) and expected[i].data != have:
            if expected[i].required:
                raise AssertionError(
                    f"item {i} missing: {describe(expected[i].data)}, "
                    f"got item {n}: {describe(have)}"
                )
            i += 1
        if i == len(expected):
            raise AssertionError(f"unexpected item {n}: {describe(have)}")
        i += 1
    missing = [k for k in range(i, len(expected)) if expected[k].required]
    if missing:
        raise AssertionError(f"items {missing} missing")
    return len(expected) - len(got)


def check_stream(
    expected: Sequence[Any],
    got: Sequence[Any],
    describe: Callable[[Any], str] = repr,
    ordered: bool = True,
) -> None:
    if not ordered:
        expected, got = sorted(expected), sorted(got)
    for i, (want, have) in enumerate(zip(expected, got)):
        if want != have:
            raise AssertionError(
                f"item {i}: expected {describe(want)}, got {describe(have)}"
            )
    if len(expected) > len(got):
        raise AssertionError(
            f"missing {describe(expected[len(got)])}"
            f" and {len(expected) - len(got) - 1} more"
        )
    if len(got) > len(expected):
        raise AssertionError(
            f"unexpected {describe(got[len(expected)])}"
            f" and {len(got) - len(expected) - 1} more"
        )


class GenericScoreboard:
    def __init__(self, monitor: GenericMonitor, model: GenericModel) -> None:
        self.monitor = monitor
        self.model = model

    async def notify(self, data: Any) -> None:
        await self.model.notify(data)

    def check(
        self, describe: Callable[[Any], str] = repr, ordered: bool = True
    ) -> None:
        check_stream(self.model.expected(), self.monitor.items, describe, ordered)
