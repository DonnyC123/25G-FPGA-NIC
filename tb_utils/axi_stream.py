import random
from dataclasses import dataclass, field
from typing import NoReturn, Self

import cocotb
from cocotb.triggers import ReadOnly, RisingEdge
from cocotb.types import Logic, LogicArray

from tb_utils.abstract_transactions import AbstractTransaction
from tb_utils.generic_driver import GenericDriver, drive
from tb_utils.generic_monitor import GenericMonitor
from tb_utils.generic_sequence import GenericSequence
from tb_utils.logic import from_logic, mask_len, mask_of, to_logic

AXI_DATA_W = 256
AXI_WORD_BYTES = AXI_DATA_W // 8


@dataclass
class AxiStreamItem(AbstractTransaction):
    data: LogicArray = field(default_factory=lambda: to_logic(b"", AXI_DATA_W))
    mask: LogicArray = field(default_factory=lambda: mask_of(0, AXI_WORD_BYTES))
    valid: Logic = field(default_factory=lambda: Logic(0))
    last: Logic = field(default_factory=lambda: Logic(0))

    @classmethod
    def from_bytes(cls, data: bytes, last: bool = False) -> Self:
        return cls(
            to_logic(data, AXI_DATA_W),
            mask_of(len(data), AXI_WORD_BYTES),
            Logic(1),
            Logic(last),
        )

    @property
    def to_data(self) -> bytes:
        return from_logic(self.data, mask_len(self.mask))


class AxiStreamDriver(GenericDriver[AxiStreamItem]):
    def __init__(self, dut, seq_item_type=None, axi=None, clk=None) -> None:
        self.axi = dut.s_axi if axi is None else axi
        self.stalls = 0
        self.holding = False
        super().__init__(dut, AxiStreamItem, clk=dut.axi_clk if clk is None else clk)

    def busy(self) -> bool:
        return super().busy() or self.holding

    async def driver_loop(self) -> NoReturn:
        await RisingEdge(self.clk)
        while True:
            item = self.next_item()
            self.holding = bool(item.valid)
            drive(self.axi, item)
            accepted = False
            while not accepted:
                await ReadOnly()
                accepted = not item.valid or bool(self.axi.ready.value)
                if not accepted:
                    self.stalls += 1
                await RisingEdge(self.clk)
            self.holding = False


class AxiStreamSequence(GenericSequence[AxiStreamItem]):
    def __init__(self, driver) -> None:
        super().__init__(driver)
        self.gap_rate = 0.0

    async def add_word(self, word: bytes, last: bool = False) -> None:
        await self.add_transaction(AxiStreamItem.from_bytes(word, last))

    async def add_frame(self, frame: bytes) -> None:
        await self.notify_subscribers(frame)
        words = [
            frame[i : i + AXI_WORD_BYTES] for i in range(0, len(frame), AXI_WORD_BYTES)
        ]
        for i, word in enumerate(words):
            if i and random.random() < self.gap_rate:
                await self.add_idle(random.randint(1, 3))
            await self.add_word(word, last=i == len(words) - 1)


class AxiStreamMonitor(GenericMonitor):
    def __init__(self, dut, output_transaction=None, axi=None, clk=None) -> None:
        self.axi = dut.m_axi if axi is None else axi
        super().__init__(dut, clk=dut.axi_clk if clk is None else clk)

    async def monitor_loop(self) -> NoReturn:
        full = (1 << len(self.axi.mask)) - 1
        partial = bytearray()
        while True:
            await RisingEdge(self.clk)
            await ReadOnly()
            if not (self.axi.valid.value and self.axi.ready.value):
                continue
            last = bool(self.axi.last.value)
            mask = int(self.axi.mask.value)
            if mask & (mask + 1) or (not last and mask != full):
                raise AssertionError(f"mask {mask:#x} last={last}")
            if mask:
                data = self.axi.data.value[8 * mask.bit_length() - 1 : 0]
                partial += data.to_bytes(byteorder="little")
            if last:
                await self.process(bytes(partial))
                partial = bytearray()


class AxiStreamReadyDriver:
    def __init__(self, ready, clk, probability: float) -> None:
        if not 0.0 <= probability <= 1.0:
            raise ValueError(f"probability must be in [0, 1], got {probability}")
        self.ready = ready
        self.clk = clk
        self.probability = probability
        cocotb.start_soon(self._loop())

    async def _loop(self) -> NoReturn:
        while True:
            self.ready.value = int(random.random() < self.probability)
            await RisingEdge(self.clk)
