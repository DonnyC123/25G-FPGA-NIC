from dataclasses import dataclass, replace
from typing import NoReturn, Self

import cocotb
from cocotb.triggers import ReadOnly, RisingEdge

from hw.common.pkg.parser_pkg import (
    ETHERTYPE_IPV4,
    ETHERTYPE_IPV6,
    ETHERTYPE_W,
    IP_PROTO_AH,
    IP_PROTO_DSTOPTS,
    IP_PROTO_FRAGMENT,
    IP_PROTO_HOPOPT,
    IP_PROTO_ROUTING,
    IP_PROTO_TCP,
    IP_PROTO_UDP,
    IP_PROTO_W,
    IPV4_ADDR_LEN,
    IPV4_HDR_BYTES,
    IPV4_OPT_EOL,
    IPV4_OPT_LSRR,
    IPV4_OPT_NOP,
    IPV4_OPT_SSRR,
    OFF_W,
    OPT_MIN_LEN,
    OPT_NOP_RUN,
    OPT_SRR_MIN_LEN,
    VLAN_COUNT_W,
)
from hw.parser.tb.eth_stage_test_base import expected_meta as expected_eth
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

CLK_PERIODS_PS = {"axi_clk": 4000}
EXT_PROTOS = (IP_PROTO_HOPOPT, IP_PROTO_ROUTING, IP_PROTO_FRAGMENT, IP_PROTO_AH, IP_PROTO_DSTOPTS)

META_FIELDS = [
    ("pos", OFF_W),
    ("eth_ok", 1),
    ("ethertype", ETHERTYPE_W),
    ("vlan_count", VLAN_COUNT_W),
    ("payload_off", OFF_W),
    ("ip_ok", 1),
    ("ip_v6", 1),
    ("addr_off", OFF_W),
    ("l4_known", 1),
    ("l4_proto", IP_PROTO_W),
    ("l4_off", OFF_W),
    ("l4_end", OFF_W),
    ("tcp_ok", 1),
    ("udp_ok", 1),
    ("csum_skip", 1),
    ("csum_pos", OFF_W),
    ("opt_done", 1),
    ("opt_off", OFF_W),
    ("dst_alt", 1),
    ("dst_alt_off", OFF_W),
]
META_W = sum(width for _, width in META_FIELDS)


@dataclass(frozen=True)
class ParseMeta:
    pos: int = 0
    eth_ok: int = 0
    ethertype: int = 0
    vlan_count: int = 0
    payload_off: int = 0
    ip_ok: int = 0
    ip_v6: int = 0
    addr_off: int = 0
    l4_known: int = 0
    l4_proto: int = 0
    l4_off: int = 0
    l4_end: int = 0
    tcp_ok: int = 0
    udp_ok: int = 0
    csum_skip: int = 0
    csum_pos: int = 0
    opt_done: int = 0
    opt_off: int = 0
    dst_alt: int = 0
    dst_alt_off: int = 0


@dataclass(frozen=True)
class ParserItem:
    frame: bytes
    meta: tuple


def decode_meta(value: int) -> ParseMeta:
    fields = {}
    shift = META_W
    for name, width in META_FIELDS:
        shift -= width
        fields[name] = (value >> shift) & ((1 << width) - 1)
    return ParseMeta(**fields)


def normalize(meta: ParseMeta, frame_len: int) -> tuple:
    eth = (meta.eth_ok, meta.vlan_count, meta.payload_off, meta.ethertype if frame_len >= meta.payload_off else None)
    ip: tuple = (meta.ip_ok,)
    if meta.ip_ok:
        ip += (meta.ip_v6, meta.addr_off, meta.l4_known)
        if meta.l4_known:
            ip += (meta.l4_proto, meta.l4_off, meta.l4_end)
    l4_ok = meta.tcp_ok or meta.udp_ok
    dst = meta.dst_alt_off if meta.dst_alt else None
    l4 = (meta.tcp_ok, meta.udp_ok, (meta.csum_pos, meta.csum_skip, dst) if l4_ok else None)
    return eth + ip + l4


def walk_options(frame: bytes, opt_off: int, opt_end: int, stages: int) -> tuple[bool, int | None]:
    def present(i: int) -> bool:
        return i < len(frame)

    dst_alt_off = None
    for _ in range(stages):
        nops = 0
        while nops < OPT_NOP_RUN and present(opt_off + nops) and frame[opt_off + nops] == IPV4_OPT_NOP:
            nops += 1
        start = opt_off + nops
        if start >= opt_end:
            return False, dst_alt_off
        if nops == OPT_NOP_RUN:
            opt_off = start
            continue
        if not (present(start) and present(start + 1)):
            return True, dst_alt_off
        opt_type, opt_len = frame[start], frame[start + 1]
        if opt_type == IPV4_OPT_EOL:
            return False, dst_alt_off
        srr = opt_type in (IPV4_OPT_LSRR, IPV4_OPT_SSRR)
        next_off = start + opt_len
        bad = opt_len < OPT_MIN_LEN or next_off > opt_end
        bad = bad or (srr and (opt_len < OPT_SRR_MIN_LEN or dst_alt_off is not None))
        if bad or (srr and not present(start + 2)):
            return True, dst_alt_off
        if srr and frame[start + 2] <= opt_len:
            dst_alt_off = next_off - IPV4_ADDR_LEN
        opt_off = next_off
        if next_off == opt_end:
            return False, dst_alt_off
    return True, dst_alt_off


def expected_meta(frame: bytes, ext_stages: int, opt_stages: int = 4) -> ParseMeta:
    n = len(frame)

    def has(*idx: int) -> bool:
        return all(i < n for i in idx)

    def be16(i: int) -> int:
        return int.from_bytes(frame[i : i + 2], "big")

    eth = expected_eth(frame)
    meta = ParseMeta(
        eth_ok=int(eth.ok),
        ethertype=eth.ethertype or 0,
        vlan_count=eth.vlan_count,
        payload_off=eth.payload_off,
    )
    p = eth.payload_off
    ip_ok = False
    ip_v6 = False
    addr_off = 0
    l4_known = False
    csum_skip = False
    dst_alt_off = None
    proto = l4_off = l4_end = 0

    if eth.ok and eth.ethertype == ETHERTYPE_IPV4:
        l4_known = has(p, p + 2, p + 3, p + 6, p + 7, p + 9)
        addr_off = p + 12
        if l4_known:
            ver, ihl = frame[p] >> 4, frame[p] & 0xF
            total = be16(p + 2)
            ip_ok = ver == 4 and ihl >= 5 and total >= ihl * 4 and be16(p + 6) & 0x3FFF == 0
            proto, l4_off, l4_end = frame[p + 9], p + ihl * 4, p + total
            if ip_ok and ihl != 5:
                csum_skip, dst_alt_off = walk_options(frame, p + IPV4_HDR_BYTES, l4_off, opt_stages)
    elif eth.ok and eth.ethertype == ETHERTYPE_IPV6:
        l4_known = has(p, p + 4, p + 5, p + 6)
        ip_v6 = True
        addr_off = p + 8
        if l4_known:
            plen = be16(p + 4)
            ip_ok = frame[p] >> 4 == 6 and plen != 0
            proto, l4_off, l4_end = frame[p + 6], p + 40, p + 40 + plen

    for _ in range(ext_stages):
        if not (ip_ok and ip_v6 and l4_known and proto in EXT_PROTOS):
            break
        o = l4_off
        csum_skip = csum_skip or proto == IP_PROTO_ROUTING
        frag = proto == IP_PROTO_FRAGMENT
        l4_known = has(o, o + 1) and (not frag or has(o + 2, o + 3))
        if not l4_known:
            break
        ext_len = frame[o + 1]
        if frag:
            size = 8
        elif proto == IP_PROTO_AH:
            size = (ext_len + 2) * 4
        else:
            size = (ext_len + 1) * 8
        frag_ok = not frag or be16(o + 2) & 0xFFF9 == 0
        ip_ok = frag_ok and o + size <= l4_end
        proto, l4_off = frame[o], o + size

    tcp_ok = False
    if ip_ok and l4_known and proto == IP_PROTO_TCP and has(l4_off + 12):
        doff = frame[l4_off + 12] >> 4
        tcp_ok = doff >= 5 and l4_off + doff * 4 <= l4_end

    udp_ok = False
    if ip_ok and l4_known and proto == IP_PROTO_UDP and has(l4_off + 4, l4_off + 5):
        udp_ok = l4_off + 8 <= l4_end and be16(l4_off + 4) == l4_end - l4_off

    return replace(
        meta,
        ip_ok=int(ip_ok),
        ip_v6=int(ip_v6),
        addr_off=addr_off,
        l4_known=int(l4_known),
        l4_proto=proto,
        l4_off=l4_off,
        l4_end=l4_end,
        tcp_ok=int(tcp_ok),
        udp_ok=int(udp_ok),
        csum_skip=int(csum_skip),
        csum_pos=l4_off + (6 if proto == IP_PROTO_UDP else 16),
        dst_alt=int(dst_alt_off is not None),
        dst_alt_off=dst_alt_off or 0,
    )


def describe(item: ParserItem) -> str:
    return f"{item.meta} len={len(item.frame)} frame={item.frame[:80].hex()}"


class PktParserModel(GenericModel):
    ext_stages = 0
    opt_stages = 0

    def process(self, data: bytes) -> None:
        meta = expected_meta(data, self.ext_stages, self.opt_stages)
        self.items.append(ParserItem(data, normalize(meta, len(data))))


class PktParserMonitor(GenericMonitor):
    def __init__(self, dut, output_transaction=None) -> None:
        self.axi = dut.m_axi
        super().__init__(dut, clk=dut.axi_clk)
        if len(dut.meta_o) != META_W:
            raise AssertionError(f"meta_o is {len(dut.meta_o)} bits, META_FIELDS give {META_W}")

    def check_words(self, frame: bytes, words: list[ParseMeta]) -> None:
        final = words[-1]
        for word in words:
            end = word.pos + AXI_WORD_BYTES
            if final.ip_ok and end > final.addr_off:
                if (word.ip_v6, word.addr_off) != (final.ip_v6, final.addr_off):
                    raise AssertionError(f"address meta at pos {word.pos}: {word} != {final}, {frame[:80].hex()}")
            word_claims_l4 = word.ip_ok and word.l4_known and end > word.l4_off
            final_has_l4 = final.ip_ok and final.l4_known and end > final.l4_off
            if word_claims_l4 or final_has_l4:
                got = (word.ip_ok, word.l4_known, word.l4_proto, word.l4_off, word.l4_end)
                want = (final.ip_ok, final.l4_known, final.l4_proto, final.l4_off, final.l4_end)
                if got != want:
                    raise AssertionError(f"l4 meta at pos {word.pos}: {got} != {want}, {frame[:80].hex()}")
            word_claims_alt = word.dst_alt and end > word.dst_alt_off
            final_has_alt = final.dst_alt and end > final.dst_alt_off
            if (final.tcp_ok or final.udp_ok) and (word_claims_alt or final_has_alt):
                if (word.dst_alt, word.dst_alt_off) != (final.dst_alt, final.dst_alt_off):
                    raise AssertionError(f"dst_alt meta at pos {word.pos}: {word} != {final}, {frame[:80].hex()}")
            for name in ("tcp_ok", "udp_ok"):
                if getattr(word, name) and not getattr(final, name):
                    raise AssertionError(f"{name} at pos {word.pos} but not at the end, {frame[:80].hex()}")
                if getattr(final, name) and end > final.csum_pos:
                    got = (getattr(word, name), word.csum_pos)
                    want = (getattr(final, name), final.csum_pos)
                    if got != want:
                        raise AssertionError(f"{name} meta at pos {word.pos}: {got} != {want}, {frame[:80].hex()}")

    async def monitor_loop(self) -> NoReturn:
        full = (1 << len(self.axi.mask)) - 1
        frame = bytearray()
        words: list[ParseMeta] = []
        while True:
            await RisingEdge(self.clk)
            await ReadOnly()
            if not (self.axi.valid.value and self.axi.ready.value):
                continue
            last = bool(self.axi.last.value)
            mask = int(self.axi.mask.value)
            if mask & (mask + 1) or (not last and mask != full):
                raise AssertionError(f"mask {mask:#x} last={last}")
            meta = decode_meta(int(self.dut.meta_o.value))
            if meta.pos != len(frame):
                raise AssertionError(f"meta pos {meta.pos}, expected {len(frame)}")
            words.append(meta)
            frame += from_logic(self.axi.data.value, mask.bit_length())
            if last:
                self.check_words(bytes(frame), words)
                await self.process(ParserItem(bytes(frame), normalize(words[-1], len(frame))))
                frame = bytearray()
                words = []


class PktParserTestBase(GenericTestBase[AxiStreamDriver, AxiStreamSequence, PktParserMonitor, PktParserModel]):
    settle_cycles = 16

    def __init__(self, dut, ready_probability: float) -> None:
        super().__init__(
            dut,
            driver=AxiStreamDriver,
            sequence_item=AxiStreamItem,
            sequence=AxiStreamSequence,
            monitor=PktParserMonitor,
            model=PktParserModel,
        )
        self.model.ext_stages = int(dut.EXT_STAGES.value)
        self.model.opt_stages = int(dut.OPT_STAGES.value)
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
        tcp = sum(1 for item in self.monitor.items if item.meta[-3])
        udp = sum(1 for item in self.monitor.items if item.meta[-2])
        skip = sum(1 for item in self.monitor.items if item.meta[-1] and item.meta[-1][1])
        cocotb.log.info("%d offloadable frames marked csum_skip", skip)
        cocotb.log.info("checked %d frames: %d tcp_ok, %d udp_ok", len(self.monitor.items), tcp, udp)
