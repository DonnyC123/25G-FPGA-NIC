import random
from collections import deque
from typing import NoReturn, Self

import cocotb
from cocotb.triggers import ReadOnly, RisingEdge

from hw.tb_utils.axi_stream import AxiStreamReadyDriver
from hw.tb_utils.generic_model import GenericModel
from hw.tb_utils.generic_test_base import GenericTestBase
from hw.tb_utils.tb_common import initialize_tb
from hw.tb_utils.tx_eth_stream import (
    TxEthStreamDriver,
    TxEthStreamItem,
    TxEthStreamMonitor,
    TxEthStreamSequence,
    frame_words,
)
from hw.tx_csum.tb.csum_model import CsumResult, encode_result, patch_frame

CLK_PERIODS_PS = {"eth_clk": 3102}
DRAIN_CYCLES = 20_000


class InsertDriver(TxEthStreamDriver):
    def __init__(self, dut, seq_item_type=None) -> None:
        super().__init__(dut, seq_item_type, stream=dut.tx_stream_i, clk=dut.eth_clk)


class ResultDriver:
    def __init__(self, dut, max_delay: int) -> None:
        self.dut = dut
        self.max_delay = max_delay
        self.pending: deque[CsumResult] = deque()
        self.popped = 0
        dut.result_valid_i.value = 0
        cocotb.start_soon(self._loop())

    async def _loop(self) -> NoReturn:
        await RisingEdge(self.dut.eth_clk)
        while True:
            if not self.pending:
                self.dut.result_valid_i.value = 0
                await RisingEdge(self.dut.eth_clk)
                continue
            for _ in range(random.randint(0, self.max_delay)):
                self.dut.result_valid_i.value = 0
                await RisingEdge(self.dut.eth_clk)
            self.dut.result_i.value = encode_result(self.pending[0])
            self.dut.result_valid_i.value = 1
            accepted = False
            while not accepted:
                await ReadOnly()
                accepted = bool(self.dut.result_ready_o.value)
                await RisingEdge(self.dut.eth_clk)
            self.pending.popleft()
            self.popped += 1


class InsertSequence(TxEthStreamSequence):
    results: ResultDriver

    async def add_frame_with_result(self, frame: bytes, result: CsumResult) -> None:
        self.results.pending.append(result)
        await self.notify_subscribers((frame, result))
        words = frame_words(frame)
        for i, word in enumerate(words):
            if i and random.random() < self.gap_rate:
                await self.add_idle(random.randint(1, 3))
            await self.add_transaction(TxEthStreamItem.from_bytes(word, i == len(words) - 1))


class InsertModel(GenericModel):
    def process(self, data: tuple[bytes, CsumResult]) -> None:
        frame, result = data
        self.items.append(patch_frame(frame, result))


class CsumInsertTestBase(GenericTestBase[InsertDriver, InsertSequence, TxEthStreamMonitor, InsertModel]):
    settle_cycles = 16

    def __init__(self, dut, ready_probability: float, max_delay: int) -> None:
        super().__init__(
            dut,
            driver=InsertDriver,
            sequence_item=TxEthStreamItem,
            sequence=InsertSequence,
            monitor=TxEthStreamMonitor,
            model=InsertModel,
        )
        self.results = ResultDriver(dut, max_delay)
        self.sequence.results = self.results
        self.ready_driver = AxiStreamReadyDriver(dut.tx_stream.ready, dut.eth_clk, ready_probability)

    @classmethod
    async def start(cls, dut, ready_probability: float = 1.0, max_delay: int = 0) -> Self:
        await initialize_tb(dut, CLK_PERIODS_PS)
        return cls(dut, ready_probability, max_delay)

    async def wait_for_driver_done(self) -> None:
        await super().wait_for_driver_done()
        for _ in range(DRAIN_CYCLES):
            if not (self.results.pending or self.dut.tx_stream.valid.value):
                return
            await RisingEdge(self.dut.eth_clk)
        raise AssertionError(f"{len(self.results.pending)} results never popped after {DRAIN_CYCLES} cycles")

    def check(self) -> None:
        self.scoreboard.check(bytes.hex)
        if self.results.popped != len(self.model.items):
            raise AssertionError(f"popped {self.results.popped} results for {len(self.model.items)} frames")
        cocotb.log.info("checked %d frames", len(self.monitor.items))
