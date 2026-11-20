from typing import Self

from cocotb.triggers import ReadOnly, RisingEdge

from hw.common.pkg import nic_regs_pkg as regs
from hw.common.pkg import rss_pkg as pkg
from hw.tb_utils.axi4_lite import Axi4LiteMaster
from hw.tb_utils.tb_common import initialize_tb

AXI_PERIOD_PS = 4000
ETH_PERIOD_PS = 2482
WORD_BYTES = regs.NIC_REGS_DATA_W // 8
WORD_MASK = (1 << regs.NIC_REGS_DATA_W) - 1
IDX_MASK = (1 << regs.NIC_REGS_IDX_W) - 1
RESP_OKAY = 0
SETTLE_CYCLES = 64

VERSION_IDX = regs.REG_VERSION_OFF // WORD_BYTES
CTRL_IDX = regs.REG_RSS_CTRL_OFF // WORD_BYTES
KEY_IDX = regs.REG_RSS_KEY_OFF // WORD_BYTES
RETA_IDX = regs.REG_RETA_OFF // WORD_BYTES


def default_key_words() -> list[int]:
    return [
        (pkg.RSS_DEFAULT_KEY >> (pkg.RSS_KEY_W - regs.NIC_REGS_DATA_W * (k + 1)))
        & WORD_MASK
        for k in range(regs.RSS_KEY_WORDS)
    ]


def merge(old: int, new: int, strb: int) -> int:
    for b in range(WORD_BYTES):
        if (strb >> b) & 1:
            byte = 0xFF << (8 * b)
            old = (old & ~byte) | (new & byte)
    return old


class NicRegsModel:
    def __init__(self) -> None:
        self.regs: dict[int, int] = {VERSION_IDX: regs.NIC_REGS_VERSION, CTRL_IDX: 0}
        for k, word in enumerate(default_key_words()):
            self.regs[KEY_IDX + k] = word
        for k in range(regs.RETA_WORDS):
            self.regs[RETA_IDX + k] = 0

    def write(self, offset: int, data: int, strb: int) -> None:
        idx = (offset // WORD_BYTES) & IDX_MASK
        if idx in self.regs and idx != VERSION_IDX:
            self.regs[idx] = merge(self.regs[idx], data, strb)

    def read(self, offset: int) -> int:
        return self.regs.get((offset // WORD_BYTES) & IDX_MASK, 0)

    @property
    def key(self) -> int:
        value = 0
        for k in range(regs.RSS_KEY_WORDS):
            value = (value << regs.NIC_REGS_DATA_W) | self.regs[KEY_IDX + k]
        return value

    @property
    def reta(self) -> int:
        return sum(
            self.regs[RETA_IDX + k] << (regs.NIC_REGS_DATA_W * k)
            for k in range(regs.RETA_WORDS)
        )

    @property
    def udp_ports_en(self) -> int:
        return (self.regs[CTRL_IDX] >> regs.RSS_CTRL_UDP_PORTS_BIT) & 1


class NicRegsTestBase:
    def __init__(self, dut) -> None:
        self.dut = dut
        self.axil = Axi4LiteMaster(dut, dut.axi_clk)
        self.model = NicRegsModel()

    @classmethod
    async def start(cls, dut, eth_period_ps: int = ETH_PERIOD_PS) -> Self:
        tb = cls(dut)
        await initialize_tb(dut, {"axi_clk": AXI_PERIOD_PS, "eth_clk": eth_period_ps})
        return tb

    async def write(self, offset: int, data: int, strb: int = 0xF) -> None:
        resp = await self.axil.write(offset, data, strb)
        assert resp == RESP_OKAY, f"write {offset:#x}: bresp {resp}"
        self.model.write(offset, data, strb)

    async def check_read(self, offset: int) -> None:
        data, resp = await self.axil.read(offset)
        assert resp == RESP_OKAY, f"read {offset:#x}: rresp {resp}"
        want = self.model.read(offset)
        assert data == want, f"read {offset:#x}: got {data:#010x}, want {want:#010x}"

    async def check_all_reads(self) -> None:
        for idx in sorted(self.model.regs):
            await self.check_read(idx * WORD_BYTES)

    def outputs_match(self) -> bool:
        return (
            int(self.dut.rss_key_o.value) == self.model.key
            and int(self.dut.reta_o.value) == self.model.reta
            and int(self.dut.udp_ports_en_o.value) == self.model.udp_ports_en
        )

    async def check_outputs(self) -> None:
        for _ in range(SETTLE_CYCLES):
            await RisingEdge(self.dut.eth_clk)
            await ReadOnly()
            if self.outputs_match():
                return
        raise AssertionError(
            f"eth outputs never matched: key {int(self.dut.rss_key_o.value):#x} "
            f"vs {self.model.key:#x}, reta {int(self.dut.reta_o.value):#x} "
            f"vs {self.model.reta:#x}, udp {int(self.dut.udp_ports_en_o.value)} "
            f"vs {self.model.udp_ports_en}"
        )
