import random

from cocotb.triggers import ReadOnly, RisingEdge

SIGNALS = (
    "awaddr",
    "awprot",
    "awvalid",
    "wdata",
    "wstrb",
    "wvalid",
    "bready",
    "araddr",
    "arprot",
    "arvalid",
    "rready",
)


class Axi4LiteMaster:
    def __init__(self, dut, clk, prefix: str = "s_axil_") -> None:
        self.dut = dut
        self.clk = clk
        self.prefix = prefix
        self.ready_probability = 1.0
        for name in SIGNALS:
            self.signal(name).value = 0

    def signal(self, name: str):
        return getattr(self.dut, self.prefix + name)

    async def _send(self, channels: list[str]) -> None:
        pending = set(channels)
        for channel in channels:
            self.signal(channel + "valid").value = 1
        while pending:
            await ReadOnly()
            accepted = {c for c in pending if self.signal(c + "ready").value}
            await RisingEdge(self.clk)
            for channel in accepted:
                self.signal(channel + "valid").value = 0
            pending -= accepted

    async def _receive(self, channel: str) -> None:
        while True:
            ready = random.random() < self.ready_probability
            self.signal(channel + "ready").value = int(ready)
            await ReadOnly()
            done = ready and bool(self.signal(channel + "valid").value)
            if done:
                await RisingEdge(self.clk)
                self.signal(channel + "ready").value = 0
                return
            await RisingEdge(self.clk)

    async def write(self, addr: int, data: int, strb: int = 0xF) -> int:
        self.signal("awaddr").value = addr
        self.signal("wdata").value = data
        self.signal("wstrb").value = strb
        await self._send(["aw", "w"])
        await self._receive("b")
        return int(self.signal("bresp").value)

    async def read(self, addr: int) -> tuple[int, int]:
        self.signal("araddr").value = addr
        await self._send(["ar"])
        while True:
            ready = random.random() < self.ready_probability
            self.signal("rready").value = int(ready)
            await ReadOnly()
            if ready and self.signal("rvalid").value:
                data = int(self.signal("rdata").value)
                resp = int(self.signal("rresp").value)
                await RisingEdge(self.clk)
                self.signal("rready").value = 0
                return data, resp
            await RisingEdge(self.clk)
