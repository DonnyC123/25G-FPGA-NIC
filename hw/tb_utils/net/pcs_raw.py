import random
from dataclasses import dataclass, field
from typing import NoReturn, Self

from cocotb.triggers import ReadOnly, RisingEdge
from cocotb.types import Logic, LogicArray

from hw.common.pkg import pcs_pkg
from hw.tb_utils.abstract_transactions import AbstractTransaction
from hw.tb_utils.bit_queue import BitQueue
from hw.tb_utils.generic_monitor import GenericMonitor
from hw.tb_utils.generic_scoreboard import Expected
from hw.tb_utils.generic_sequence import GenericSequence
from hw.tb_utils.logic import from_logic, to_logic
from hw.tb_utils.net.packets import add_fcs
from hw.tb_utils.net.pcs_blocks import TERM, PcsBlock, corruptions, encode, idle_block
from hw.tb_utils.net.pma_gearbox import BitChunk, GearboxDriver
from hw.tb_utils.net.scrambler import Scrambler

RAW_W = 64


@dataclass
class PcsRawItem(AbstractTransaction):
    raw_data_i: LogicArray = field(default_factory=lambda: to_logic(b"", RAW_W))
    raw_valid_i: Logic = field(default_factory=lambda: Logic(0))

    @classmethod
    def from_bytes(cls, data: bytes) -> Self:
        return cls(to_logic(data, RAW_W), Logic(1))

    @property
    def to_data(self) -> bytes:
        return from_logic(self.raw_data_i)


class PcsRawDriver(GearboxDriver):
    def __init__(self, dut, seq_item_type=None, clk=None) -> None:
        super().__init__(dut, PcsRawItem, RAW_W, clk=clk)


class PcsRawSequence(GenericSequence[BitChunk]):
    def __init__(self, driver) -> None:
        super().__init__(driver)
        self.scrambler = Scrambler()
        self.required = True
        self.bad_fcs = 0
        self.corrupted = 0

    async def add_blocks(self, blocks: list[PcsBlock]) -> None:
        for block in blocks:
            data = self.scrambler.scramble(block).to_bytes()
            await self.add_transaction(BitChunk(data, pcs_pkg.PCS_BLOCK_W))

    async def add_idle(self, count: int = 1) -> None:
        await self.add_blocks([idle_block()] * count)

    async def add_frame(self, frame: bytes, sof_lane: int = 0) -> None:
        wire = add_fcs(frame)
        await self.notify_subscribers(Expected(wire, self.required))
        await self.add_blocks(encode(wire, sof_lane))

    async def add_bad_fcs_frame(self, frame: bytes, sof_lane: int = 0) -> None:
        wire = bytearray(add_fcs(frame))
        wire[random.randrange(len(wire))] ^= 1 << random.randrange(8)
        self.bad_fcs += 1
        await self.add_blocks(encode(bytes(wire), sof_lane))

    async def add_corrupted_frame(
        self, frame: bytes, sof_lane: int = 0, kind: str | None = None
    ) -> None:
        found = corruptions(encode(add_fcs(frame), sof_lane))
        self.corrupted += 1
        await self.add_blocks(found[kind or random.choice(list(found))])

    async def add_garbage(self, width: int) -> None:
        data = random.getrandbits(width).to_bytes((width + 7) // 8, "little")
        await self.add_transaction(BitChunk(data, width))


class PcsRawMonitor(GenericMonitor):
    def __init__(self, dut, output_transaction=None, clk=None, rst=None) -> None:
        self.rst = dut.rst if rst is None else rst
        self.raw = BitQueue()
        self.descrambler = Scrambler()
        self.blocks: list[PcsBlock] = []
        self.terms = 0
        self.bubbles = 0
        self.started = False
        super().__init__(dut, clk=clk)

    def reset(self) -> None:
        self.raw = BitQueue()
        self.descrambler = Scrambler()
        self.started = False

    async def monitor_loop(self) -> NoReturn:
        raw_w = len(self.dut.raw_data_o)
        while True:
            await RisingEdge(self.clk)
            await ReadOnly()
            if self.rst.value:
                self.reset()
                continue
            if not self.dut.raw_valid_o.value:
                self.bubbles += self.started
                continue
            self.started = True
            self.raw.push(from_logic(self.dut.raw_data_o.value), raw_w)
            while len(self.raw) >= pcs_pkg.PCS_BLOCK_W:
                block = PcsBlock.from_bytes(self.raw.pop(pcs_pkg.PCS_BLOCK_W))
                block = self.descrambler.descramble(block)
                self.blocks.append(block)
                if block.sync == pcs_pkg.CTRL_SYNC and block.payload[0] in TERM:
                    self.terms += 1
