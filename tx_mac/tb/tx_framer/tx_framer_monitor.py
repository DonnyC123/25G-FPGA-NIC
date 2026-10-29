from typing import NoReturn

from cocotb.triggers import ReadOnly, RisingEdge

from common.pkg import pcs_pkg
from tb_utils.generic_monitor import GenericMonitor
from tb_utils.net.pcs_blocks import TERM, PcsBlock


class TxFramerMonitor(GenericMonitor):
    def __init__(self, dut, output_transaction=None) -> None:
        self.blocks: list[PcsBlock] = []
        self.terms = 0
        super().__init__(dut, clk=dut.clk)

    async def monitor_loop(self) -> NoReturn:
        while True:
            await RisingEdge(self.clk)
            await ReadOnly()
            if not self.dut.out_valid_o.value:
                continue
            payload = int(self.dut.out_data_o.value).to_bytes(
                pcs_pkg.PCS_PAYLOAD_BYTES, "little"
            )
            block = PcsBlock(int(self.dut.out_control_o.value), payload)
            self.blocks.append(block)
            if block.sync == pcs_pkg.CTRL_SYNC and block.payload[0] in TERM:
                self.terms += 1
