from hw.tb_utils.generic_model import GenericModel


class AlignmentFinderModel(GenericModel):
    def __init__(self) -> None:
        super().__init__()
        self.sent: dict[int, bytes] = {}
        self.garbage: list[int] = []

    def process(self, data: tuple[int, bytes | None]) -> None:
        position, block = data
        if block is None:
            self.garbage.append(position)
        else:
            self.sent[position] = block
