from dataclasses import dataclass
from typing import NoReturn, Self

import cocotb
from cocotb.triggers import ReadOnly, RisingEdge

from hw.common.pkg.parser_pkg import (
    ETH_TYPE_OFF,
    ETHERTYPE_BYTES,
    ETHERTYPE_MIN,
    ETHERTYPE_QINQ,
    ETHERTYPE_VLAN,
    MAX_VLANS,
    VLAN_TAG_BYTES,
)
from hw.tb_utils.axi_stream import (
    AXI_WORD_BYTES,
    AxiStreamDriver,
    AxiStreamItem,
    AxiStreamReadyDriver,
    AxiStreamSequence,
)
from hw.tb_utils.generic_model import GenericModel
from hw.tb_utils.generic_monitor import GenericMonitor
from hw.tb_utils.generic_test_base import GenericTestBase
from hw.tb_utils.logic import from_logic
from hw.tb_utils.tb_common import initialize_tb

TAG_TYPES = (ETHERTYPE_VLAN, ETHERTYPE_QINQ)
CLK_PERIODS_PS = {"axi_clk": 4000}


@dataclass(frozen=True)
class EthMeta:
    ok: bool
    ethertype: int | None
    vlan_count: int
    payload_off: int


@dataclass(frozen=True)
class EthStageItem:
    frame: bytes
    meta: EthMeta


def expected_meta(frame: bytes) -> EthMeta:
    length = min(len(frame), AXI_WORD_BYTES)
    off = ETH_TYPE_OFF
    vlans = 0
    while True:
        present = length >= off + ETHERTYPE_BYTES
        ethertype = int.from_bytes(frame[off : off + ETHERTYPE_BYTES], "big") if present else None
        is_tag = ethertype in TAG_TYPES
        if present and is_tag and vlans < MAX_VLANS:
            vlans += 1
            off += VLAN_TAG_BYTES
            continue
        ok = present and not is_tag and ethertype is not None and ethertype >= ETHERTYPE_MIN
        return EthMeta(ok, ethertype, vlans, off + ETHERTYPE_BYTES)


def describe(item: EthStageItem) -> str:
    return f"{item.meta} len={len(item.frame)} frame={item.frame[:24].hex()}"


class EthStageModel(GenericModel):
    def process(self, data: bytes) -> None:
        self.items.append(EthStageItem(data, expected_meta(data)))


class EthStageMonitor(GenericMonitor):
    def __init__(self, dut, output_transaction=None) -> None:
        self.axi = dut.m_axi
        super().__init__(dut, clk=dut.axi_clk)

    def read_meta(self, frame_len: int) -> EthMeta:
        payload_off = int(self.dut.meta_payload_off.value)
        ethertype = int(self.dut.meta_ethertype.value)
        return EthMeta(
            bool(self.dut.meta_eth_ok.value),
            ethertype if frame_len >= payload_off else None,
            int(self.dut.meta_vlan_count.value),
            payload_off,
        )

    async def monitor_loop(self) -> NoReturn:
        full = (1 << len(self.axi.mask)) - 1
        frame = bytearray()
        raw_meta: tuple[int, ...] | None = None
        while True:
            await RisingEdge(self.clk)
            await ReadOnly()
            if not (self.axi.valid.value and self.axi.ready.value):
                continue
            last = bool(self.axi.last.value)
            mask = int(self.axi.mask.value)
            if mask & (mask + 1) or (not last and mask != full):
                raise AssertionError(f"mask {mask:#x} last={last}")
            pos = int(self.dut.meta_pos.value)
            if pos != len(frame):
                raise AssertionError(f"meta pos {pos}, expected {len(frame)}")
            word_meta = (
                int(self.dut.meta_eth_ok.value),
                int(self.dut.meta_ethertype.value),
                int(self.dut.meta_vlan_count.value),
                int(self.dut.meta_payload_off.value),
            )
            if raw_meta is None:
                raw_meta = word_meta
            elif word_meta != raw_meta:
                raise AssertionError(f"meta changed mid-frame at pos {pos}: {word_meta} != {raw_meta}")
            frame += from_logic(self.axi.data.value, mask.bit_length())
            if last:
                await self.process(EthStageItem(bytes(frame), self.read_meta(len(frame))))
                frame = bytearray()
                raw_meta = None


class EthStageTestBase(GenericTestBase[AxiStreamDriver, AxiStreamSequence, EthStageMonitor, EthStageModel]):
    settle_cycles = 8

    def __init__(self, dut, ready_probability: float) -> None:
        super().__init__(
            dut,
            driver=AxiStreamDriver,
            sequence_item=AxiStreamItem,
            sequence=AxiStreamSequence,
            monitor=EthStageMonitor,
            model=EthStageModel,
        )
        self.ready_driver = AxiStreamReadyDriver(dut.m_axi.ready, dut.axi_clk, ready_probability)

    @classmethod
    async def start(cls, dut, ready_probability: float = 1.0) -> Self:
        await initialize_tb(dut, CLK_PERIODS_PS)
        return cls(dut, ready_probability)

    async def wait_for_driver_done(self) -> None:
        await super().wait_for_driver_done()
        while self.dut.m_axi.valid.value:
            await RisingEdge(self.dut.axi_clk)

    def check(self) -> None:
        self.scoreboard.check(describe)
        cocotb.log.info("checked %d frames", len(self.monitor.items))
