from rx_pcs.tb.pcs_decoder.pcs_decoder_model import event
from rx_pcs.tb.pcs_decoder.pcs_decoder_transaction import (
    PcsDecoderOutput,
    PcsDecoderTransaction,
)
from tb_utils.generic_monitor import GenericMonitor
from tb_utils.net.pcs_blocks import PcsEvent

ERROR_EVENTS = {
    "invalid_sync": PcsEvent.BAD_SYNC,
    "unexpected_sync": PcsEvent.UNEXPECTED_DATA,
    "unexpected_eof": PcsEvent.UNEXPECTED_TERM,
    "ctrl_parsing": PcsEvent.BAD_CTRL,
}


class PcsDecoderMonitor(GenericMonitor[PcsDecoderTransaction]):
    def __init__(self, dut, output_transaction=None) -> None:
        self.partial = bytearray()
        super().__init__(dut, output_transaction)

    async def process(self, data: PcsDecoderOutput) -> None:
        if data.data is not None:
            self.partial += data.data
            if data.last:
                await super().process(event(PcsEvent.FRAME, bytes(self.partial)))
                self.partial = bytearray()
        for name in data.errors:
            await super().process(event(ERROR_EVENTS[name], b""))
        if data.drop:
            await super().process(event(PcsEvent.DROP, b""))
            self.partial = bytearray()
