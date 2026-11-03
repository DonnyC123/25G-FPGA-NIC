from hw.rx_mac.tb.crc_checker.crc_checker_model import CrcEvent, event
from hw.rx_mac.tb.crc_checker.crc_checker_sequence_item import CrcWord
from hw.rx_mac.tb.crc_checker.crc_checker_transaction import CrcCheckerTransaction
from hw.tb_utils.generic_monitor import GenericMonitor


class CrcCheckerMonitor(GenericMonitor[CrcCheckerTransaction]):
    def __init__(self, dut, output_transaction=None) -> None:
        self.partial = bytearray()
        super().__init__(dut, output_transaction)

    async def process(self, data: CrcWord) -> None:
        if data.data is not None:
            self.partial += data.data
        if data.drop:
            await super().process(event(CrcEvent.DROP, bytes(self.partial)))
            self.partial = bytearray()
        elif data.last:
            await super().process(event(CrcEvent.SEND, bytes(self.partial)))
            self.partial = bytearray()
