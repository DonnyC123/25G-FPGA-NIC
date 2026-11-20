import random
from enum import Enum, auto

import cocotb

from hw.common.pkg import rss_pkg
from hw.common.pkg.rx_meta_pkg import RX_META_TYPE_OFF
from hw.rx_parser.tb.parser_frames import valid_frame
from hw.rx_rss.tb.rss_model import HashType
from hw.rx_top.tb.rx_top_test_base import RxTopTestBase
from hw.tb_utils.net.packets import ETH_MAX_LEN, random_ip_frame
from hw.tb_utils.net.pcs_blocks import corruptions, encode
from hw.tb_utils.random_utils import pick, random_frame


class Action(Enum):
    FRAME = auto()
    IP = auto()
    IDLE = auto()
    CORRUPT = auto()
    BAD_FCS = auto()
    SLIP = auto()


ACTION_WEIGHTS = {
    Action.FRAME: 45,
    Action.IP: 10,
    Action.IDLE: 22,
    Action.CORRUPT: 10,
    Action.BAD_FCS: 10,
    Action.SLIP: 3,
}


def random_lane() -> int:
    return random.choice((0, 4))


@cocotb.test()
async def test_frame_sizes(dut) -> None:
    tb = await RxTopTestBase.start(dut)
    seq = tb.sequence
    for lane in (0, 4):
        for length in range(max(lane, 1), 100):
            await seq.add_frame(random.randbytes(length), lane)
            await seq.add_idle(2)
    await tb.finish()


@cocotb.test()
async def test_back_to_back(dut) -> None:
    tb = await RxTopTestBase.start(dut)
    seq = tb.sequence
    for _ in range(60):
        await seq.add_frame(random_frame(4, 128), random_lane())
    await tb.finish()


@cocotb.test()
async def test_ip_frames(dut) -> None:
    tb = await RxTopTestBase.start(dut)
    seq = tb.sequence
    for i in range(20):
        await seq.add_frame(random_ip_frame(ipv6=i % 2 == 1, fcs=False), random_lane())
        await seq.add_idle(random.randint(1, 4))
    await tb.finish()


@cocotb.test()
async def test_bubbles(dut) -> None:
    tb = await RxTopTestBase.start(dut)
    tb.driver.bubble_rate = 0.3
    seq = tb.sequence
    for _ in range(40):
        await seq.add_frame(random_frame(4, 128), random_lane())
        await seq.add_idle(random.randint(0, 3))
    await tb.finish()


@cocotb.test()
async def test_backpressure(dut) -> None:
    tb = await RxTopTestBase.start(dut, ready_probability=0.3)
    seq = tb.sequence
    for _ in range(60):
        await seq.add_frame(random_frame(4, 128), random_lane())
        await seq.add_idle(random.randint(1, 4))
    await tb.finish()


@cocotb.test()
async def test_fifo_overflow_recovers(dut) -> None:
    tb = await RxTopTestBase.start(dut, ready_probability=0.05)
    seq = tb.sequence
    for _ in range(40):
        await seq.add_frame(random_frame(200, 600), random_lane())
        await seq.add_idle(2)
    await tb.set_ready(1.0)
    for _ in range(40):
        await seq.add_frame(random_frame(4, 600), random_lane())
        await seq.add_idle(random.randint(0, 2))
    await tb.finish()
    if tb.drops()["overflow_drops_o"] == tb.base_drops["overflow_drops_o"]:
        raise AssertionError("FIFO never overflowed")


@cocotb.test()
async def test_largest_frame(dut) -> None:
    tb = await RxTopTestBase.start(dut)
    seq = tb.sequence
    for _ in range(5):
        await seq.add_frame(random.randbytes(ETH_MAX_LEN))
        await seq.add_idle(2)
    await tb.finish()


@cocotb.test()
async def test_corrupted_frames_dropped(dut) -> None:
    tb = await RxTopTestBase.start(dut)
    seq = tb.sequence
    for lane in (0, 4):
        for kind in corruptions(encode(bytes(30), lane)):
            await seq.add_corrupted_frame(random.randbytes(30), lane, kind)
            await seq.add_frame(random_frame(4, 128), random_lane())
            await seq.add_idle(2)
    await tb.finish()


@cocotb.test()
async def test_bad_fcs_dropped(dut) -> None:
    tb = await RxTopTestBase.start(dut)
    seq = tb.sequence
    for lane in (0, 4):
        for length in range(4, 80):
            await seq.add_bad_fcs_frame(random.randbytes(length), lane)
            await seq.add_frame(random_frame(4, 128), random_lane())
    await tb.finish()


@cocotb.test()
async def test_relock_after_slip(dut) -> None:
    tb = await RxTopTestBase.start(dut)
    seq = tb.sequence
    for _ in range(5):
        await seq.add_frame(random_frame(4, 128), random_lane())
        await seq.add_garbage(random.randint(1, 65))
        await tb.relock()
        await seq.add_frame(random_frame(4, 128), random_lane())
    await tb.finish()


@cocotb.test()
async def test_reset_mid_frame(dut) -> None:
    tb = await RxTopTestBase.start(dut)
    seq = tb.sequence
    await seq.add_blocks(encode(random.randbytes(64))[:4])
    await tb.reset()
    await seq.add_frame(random_frame(4, 128))
    await tb.finish()


@cocotb.test()
async def test_random_traffic(dut) -> None:
    tb = await RxTopTestBase.start(dut)
    seq = tb.sequence
    for _ in range(300):
        lane = random_lane()
        match pick(ACTION_WEIGHTS):
            case Action.FRAME:
                await seq.add_frame(random_frame(4, 128), lane)
            case Action.IP:
                await seq.add_frame(random_ip_frame(random.random() < 0.5, fcs=False), lane)
            case Action.IDLE:
                await seq.add_idle(random.randint(1, 4))
            case Action.CORRUPT:
                await seq.add_corrupted_frame(random_frame(4, 128), lane)
            case Action.BAD_FCS:
                await seq.add_bad_fcs_frame(random_frame(4, 128), lane)
            case Action.SLIP:
                await seq.add_garbage(random.randint(1, 65))
                await tb.relock()
    await tb.finish()


@cocotb.test()
async def test_rss_metadata(dut) -> None:
    queues = rss_pkg.RSS_MAX_QUEUES
    reta = [random.randrange(queues) for _ in range(rss_pkg.RETA_SIZE)]
    tb = await RxTopTestBase.start(
        dut,
        key=random.randbytes(rss_pkg.RSS_KEY_BYTES),
        udp_ports_en=True,
        reta=reta,
    )
    seq = tb.sequence
    for _ in range(150):
        await seq.add_frame(valid_frame(), random_lane())
        await seq.add_idle(random.randint(0, 2))
    await tb.finish()
    types = {item[RX_META_TYPE_OFF] for item in tb.monitor.items}
    assert {HashType.L3, HashType.L4} <= types
