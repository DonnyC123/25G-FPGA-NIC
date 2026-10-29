from dataclasses import dataclass, field, fields

from cocotb.types import LogicArray

from common.pkg import pcs_pkg
from tb_utils.abstract_transactions import AbstractTransaction
from tb_utils.logic import from_logic

DROP_BIT = 0
LAST_BIT = 1
VALID_BIT = 2
LAST_BYTES_LSB = 3
DATA_LSB = LAST_BYTES_LSB + pcs_pkg.LAST_BYTES_W
ETH_STREAM_W = DATA_LSB + pcs_pkg.PCS_PAYLOAD_W
ERROR_FIELDS = tuple(f.name for f in fields(pcs_pkg.pcs_decoder_error_t))
ERROR_W = len(ERROR_FIELDS)


@dataclass(frozen=True)
class PcsDecoderOutput:
    data: bytes | None
    last: bool
    drop: bool
    errors: tuple[str, ...]


@dataclass
class PcsDecoderTransaction(AbstractTransaction):
    eth_stream_o: LogicArray = field(
        default_factory=lambda: LogicArray.from_unsigned(0, ETH_STREAM_W)
    )
    pcs_decoder_error_o: LogicArray = field(
        default_factory=lambda: LogicArray.from_unsigned(0, ERROR_W)
    )

    @property
    def to_data(self) -> PcsDecoderOutput | None:
        stream = self.eth_stream_o
        drop = bool(stream[DROP_BIT])
        valid = bool(stream[VALID_BIT])
        errors = tuple(
            name
            for i, name in enumerate(ERROR_FIELDS)
            if self.pcs_decoder_error_o[ERROR_W - 1 - i]
        )
        data = None
        last = False
        if valid and not drop:
            last = bool(stream[LAST_BIT])
            count = pcs_pkg.PCS_PAYLOAD_BYTES
            if last:
                count = int(stream[DATA_LSB - 1 : LAST_BYTES_LSB])
            data = b""
            if count:
                top = DATA_LSB + pcs_pkg.BYTE_W * count - 1
                data = from_logic(stream[top:DATA_LSB])
        if data is None and not drop and not errors:
            return None
        return PcsDecoderOutput(data, last, drop, errors)
