import cocotb

from hw.parser.tb.parser_frames import KNOWN_FRAMES, random_frame
from hw.parser.tb.pkt_parser_test_base import PktParserTestBase
from hw.tb_utils.net.packets import pad


@cocotb.test()
async def test_known_frames(dut) -> None:
    tb = await PktParserTestBase.start(dut)
    for packet in KNOWN_FRAMES:
        await tb.sequence.add_frame(pad(bytes(packet)))
    await tb.finish()


@cocotb.test()
async def test_truncated_known_frames(dut) -> None:
    tb = await PktParserTestBase.start(dut)
    for packet in KNOWN_FRAMES:
        frame = pad(bytes(packet))
        for length in range(1, min(len(frame), 140)):
            await tb.sequence.add_frame(frame[:length])
    await tb.finish()


@cocotb.test()
async def test_random_frames(dut) -> None:
    tb = await PktParserTestBase.start(dut)
    for _ in range(3000):
        await tb.sequence.add_frame(random_frame())
    await tb.finish()


@cocotb.test()
async def test_random_backpressure(dut) -> None:
    tb = await PktParserTestBase.start(dut, ready_probability=0.4)
    tb.sequence.gap_rate = 0.3
    for _ in range(1500):
        await tb.sequence.add_frame(random_frame())
    await tb.finish()
