"""pytest runner for the tx_cdc_top + wire_emulator + rx_top loopback test."""

import os
import shutil
from pathlib import Path

REPO_ROOT     = Path(__file__).resolve().parents[2]
LOOPBACK_ROOT = REPO_ROOT / "loopback"
TX_FIFO_DIR   = REPO_ROOT / "tx_fifo"
TX_MAC_DIR    = REPO_ROOT / "tx_mac"
TX_PCS_DIR    = REPO_ROOT / "tx_pcs"
RX_PCS_DIR    = REPO_ROOT / "rx_pcs"
RX_FIFO_DIR   = REPO_ROOT / "rx_fifo"
def _pcs_sources() -> list[Path]:
    return [
        TX_PCS_DIR / "rtl" / "tx_axis_if.sv",
        REPO_ROOT / "common" / "pkg" / "pcs_pkg.sv",
        TX_PCS_DIR / "rtl" / "pcs_generator.sv",
    ]


sources = [
    REPO_ROOT / "rtl_utils" / "if" / "axi_stream_if.sv",
    REPO_ROOT / "rtl_utils" / "data_pipeline.sv",
    REPO_ROOT / "rtl_utils" / "data_status_pipeline.sv",

    # TX side
    TX_FIFO_DIR / "rtl" / "tx_subsystem_pkg.sv",
    TX_FIFO_DIR / "rtl" / "tx_async_fifo.sv",
    TX_FIFO_DIR / "rtl" / "tx_subsystem.sv",
    *_pcs_sources(),
    TX_PCS_DIR / "rtl" / "scrambler.sv",
    TX_PCS_DIR / "rtl" / "debubbler.sv",
    TX_MAC_DIR / "rtl" / "pad_inserter.sv",
    TX_MAC_DIR / "rtl" / "crc_inserter.sv",
    TX_MAC_DIR / "rtl" / "tx_mac.sv",
    TX_PCS_DIR / "rtl" / "tx_pcs.sv",
    TX_PCS_DIR / "tb" / "tx_cdc_top.sv",

    # RX side
    RX_FIFO_DIR / "rtl" / "rx_fifo_pkg.sv",
    RX_FIFO_DIR / "rtl" / "rx_async_fifo.sv",
    RX_FIFO_DIR / "rtl" / "rx_fifo_ctrl.sv",
    RX_PCS_DIR / "rtl" / "alignment_finder.sv",
    RX_PCS_DIR / "rtl" / "pcs_decoder.sv",
    RX_PCS_DIR / "rtl" / "block_sync.sv",
    RX_PCS_DIR / "rtl" / "descrambler.sv",
    RX_PCS_DIR / "rtl" / "rx_pcs.sv",
    RX_PCS_DIR / "tb" / "rx_top.sv",

    # Loopback glue
    LOOPBACK_ROOT / "rtl" / "wire_emulator.sv",
    LOOPBACK_ROOT / "tb"  / "loopback_top.sv",
]


def _select_simulator() -> str:
    sim_env = os.environ.get("SIM")
    if sim_env:
        return sim_env
    if shutil.which("vsim") is not None:
        return "questa"
    if shutil.which("verilator") is not None:
        return "verilator"
    raise SystemExit(
        "ERROR: No supported simulator found in PATH (expected 'vsim' or 'verilator'). "
        "Set SIM to override."
    )


def test_loopback():
    from cocotb_tools.runner import get_runner

    sim_name = _select_simulator()
    sim = get_runner(sim_name)

    pythonpath = str(REPO_ROOT) + os.pathsep + os.environ.get("PYTHONPATH", "")
    os.environ["PYTHONPATH"] = pythonpath

    parameters = {
        "OFFSET_BITS": int(os.environ.get("LB_OFFSET_BITS", 17)),
        "FIFO_DEPTH":  int(os.environ.get("LB_FIFO_DEPTH", 64)),
        "DESC_DEPTH":  int(os.environ.get("LB_DESC_DEPTH", 32)),
        "NUM_QUEUES":  int(os.environ.get("LB_NUM_QUEUES", 4)),
    }

    sim_test_args = ["-voptargs=+acc", "-t", "ps"] if sim_name == "questa" else []

    sim.build(
        sources=[str(s) for s in sources],
        hdl_toplevel="loopback_top",
        build_dir=str(REPO_ROOT / "sim_build" / "loopback"),
        parameters=parameters,
        timescale=("1ns", "1ps"),
        waves=True,
    )

    sim.test(
        hdl_toplevel="loopback_top",
        test_module="loopback.tb.loopback_test",
        waves=True,
        test_args=sim_test_args,
        timescale=("1ns", "1ps"),
        extra_env={
            "TOPLEVEL_LANG": "verilog",
            "PYTHONPATH": pythonpath,
        },
    )


if __name__ == "__main__":
    test_loopback()
