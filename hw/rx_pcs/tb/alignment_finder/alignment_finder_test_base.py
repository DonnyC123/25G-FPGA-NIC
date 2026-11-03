from typing import Self

from cocotb.triggers import RisingEdge

from hw.common.pkg.pcs_pkg import PCS_BLOCK_W
from hw.rx_pcs.tb.alignment_finder.alignment_finder_driver import AlignmentFinderDriver
from hw.rx_pcs.tb.alignment_finder.alignment_finder_model import AlignmentFinderModel
from hw.rx_pcs.tb.alignment_finder.alignment_finder_monitor import (
    AlignmentFinderMonitor,
    HeaderResult,
)
from hw.rx_pcs.tb.alignment_finder.alignment_finder_sequence import (
    AlignmentFinderSequence,
)
from hw.rx_pcs.tb.alignment_finder.alignment_finder_sequence_item import (
    AlignmentFinderSequenceItem,
)
from hw.rx_pcs.tb.alignment_finder.alignment_finder_transaction import (
    AlignmentFinderTransaction,
)
from hw.tb_utils.generic_scoreboard import check_stream
from hw.tb_utils.generic_test_base import GenericTestBase
from hw.tb_utils.net.pma_gearbox import PmaGearboxModel
from hw.tb_utils.tb_common import initialize_tb

CHUNK = 64


class AlignmentFinderTestBase(
    GenericTestBase[
        AlignmentFinderDriver,
        AlignmentFinderSequence,
        AlignmentFinderMonitor,
        AlignmentFinderModel,
    ]
):
    idle_cycles = 0
    settle_cycles = 2

    def __init__(self, dut, slip_latency: int = 1) -> None:
        super().__init__(
            dut,
            driver=AlignmentFinderDriver,
            sequence_item=AlignmentFinderSequenceItem,
            sequence=AlignmentFinderSequence,
            monitor=AlignmentFinderMonitor,
            output_transaction=AlignmentFinderTransaction,
            model=AlignmentFinderModel,
        )
        self.driver.gearbox = PmaGearboxModel(slip_latency)
        self.driver.add_subscriber(self.monitor.on_driven)
        self.good_count = int(dut.GOOD_COUNT.value)
        self.bad_count = int(dut.BAD_COUNT.value)
        self.bad_window = int(dut.BAD_WINDOW.value)
        self.bitslip_wait = int(dut.BITSLIP_WAIT.value)

    @classmethod
    async def start(
        cls, dut, slip_latency: int = 1, bubble_rate: float = 0.0
    ) -> Self:
        await initialize_tb(dut)
        tb = cls(dut, slip_latency)
        tb.driver.bubble_rate = bubble_rate
        return tb

    def check(self) -> None:
        expected: list[tuple[int, bytes | None]] = []
        actual: list[tuple[int, bytes]] = []
        aligned_at = None
        for h in self.headers():
            if not h.aligned:
                aligned_at = None
                continue
            if aligned_at is None:
                aligned_at = h.position
            if any(aligned_at < g <= h.position for g in self.model.garbage):
                continue
            expected.append((h.position, self.model.sent.get(h.position)))
            actual.append((h.position, h.block))
        check_stream(expected, actual)

    def headers(self) -> list[HeaderResult]:
        return self.monitor.items

    def aligned(self) -> bool:
        headers = self.headers()
        return bool(headers) and headers[-1].aligned

    def edges(self) -> tuple[list[int], list[int]]:
        headers = self.headers()
        rises = [
            i
            for i, h in enumerate(headers)
            if h.aligned and (i == 0 or not headers[i - 1].aligned)
        ]
        falls = [
            i
            for i, h in enumerate(headers)
            if not h.aligned and i > 0 and headers[i - 1].aligned
        ]
        return rises, falls

    def slips(self, start: int, stop: int) -> list[int]:
        headers = self.headers()
        return [i for i in range(start, stop) if headers[i].bitslip]

    async def run_until(self, want_aligned: bool) -> None:
        start = len(self.headers())
        limit = (
            PCS_BLOCK_W * (self.good_count + self.bitslip_wait + 8) + self.good_count
        )
        while self.aligned() != want_aligned:
            seen = len(self.headers()) - start
            assert seen < limit, (
                f"aligned_o never went {int(want_aligned)} in {limit} headers"
            )
            if self.driver.seq_item_queue.qsize() < CHUNK:
                await self.sequence.add_good(CHUNK)
            await RisingEdge(self.dut.clk)

    def check_acquired(self, rise: int, after: int, slips: int) -> None:
        slip_at = self.slips(after + 1, rise)
        assert len(slip_at) == slips, (
            f"expected {slips} bitslips before aligning, got {len(slip_at)}"
        )
        start = slip_at[-1] if slip_at else after
        expected = start + (self.bitslip_wait if slip_at else 0) + self.good_count
        assert rise == expected, f"aligned on header {rise}, expected {expected}"

    async def lose_by_bad_headers(self) -> None:
        await self.wait_for_driver_done()
        headers = self.headers()
        rise = self.edges()[0][-1]
        left_in_window = self.bad_window - (len(headers) - rise - 1) % self.bad_window
        if left_in_window < self.bad_count:
            await self.sequence.add_good(left_in_window)
        await self.sequence.add_bad(self.bad_count)
        await self.run_until(False)
        await self.run_until(True)

        headers = self.headers()
        rises, falls = self.edges()
        assert not headers[falls[-1]].good, (
            f"lost alignment on a good header {falls[-1]}"
        )
        assert not headers[falls[-1]].bitslip
        self.check_acquired(rises[-1], falls[-1], 0)

    async def lose_by_glitch(self, bits: int) -> None:
        before = self.edges()[0][-1]
        await self.sequence.add_garbage(bits)
        await self.run_until(False)
        await self.run_until(True)
        self.check_acquired(self.edges()[0][-1], before, bits)
