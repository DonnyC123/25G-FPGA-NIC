# Pin constraints for nic_top on the AS02MC04 (xcku3p-ffvb676-2-e).
# Locations taken from the board file: as02mc04/1.0/part0_pins.xml

# ---------------------------------------------------------------------------
# Clocks
# ---------------------------------------------------------------------------

# 100 MHz onboard oscillator (freerun clock)
set_property -dict {PACKAGE_PIN E18 IOSTANDARD LVDS} [get_ports diff_100mhz_clk_p]
set_property -dict {PACKAGE_PIN D18 IOSTANDARD LVDS} [get_ports diff_100mhz_clk_n]
create_clock -period 10.000 -name freerun_clk [get_ports diff_100mhz_clk_p]

# 156.25 MHz SFP GT reference clock (GTY Quad 227)
set_property PACKAGE_PIN K7 [get_ports sfp_mgt_clk_p]
set_property PACKAGE_PIN K6 [get_ports sfp_mgt_clk_n]
create_clock -period 6.400 -name sfp_mgt_clk [get_ports sfp_mgt_clk_p]

# 100 MHz PCIe reference clock (from the host slot). The clock itself is
# created by the block design's util_ds_buf IP, so only the pins go here.
set_property PACKAGE_PIN T7 [get_ports pcie_refclk_clk_p]
set_property PACKAGE_PIN T6 [get_ports pcie_refclk_clk_n]

# ---------------------------------------------------------------------------
# Clock-domain crossings
# ---------------------------------------------------------------------------

# The PCIe AXI clock (250 MHz) and the 25G GT user clocks (402.83 MHz) come
# from unrelated oscillators. They only cross through async_packet_fifo
# (gray-coded pointers + 2-flop synchronizers) and rst_sync, so bound each
# crossing to one destination clock period instead of timing it as synchronous.
set_max_delay -datapath_only -from [get_clocks axi_aclk] -to [get_clocks {gtwiz_userclk_tx_srcclk_out[0]}] 2.482
set_max_delay -datapath_only -from [get_clocks {gtwiz_userclk_tx_srcclk_out[0]}] -to [get_clocks axi_aclk] 4.000
set_max_delay -datapath_only -from [get_clocks axi_aclk] -to [get_clocks {gtwiz_userclk_rx_srcclk_out[0]}] 2.482
set_max_delay -datapath_only -from [get_clocks {gtwiz_userclk_rx_srcclk_out[0]}] -to [get_clocks axi_aclk] 4.000

# ---------------------------------------------------------------------------
# PCIe
# ---------------------------------------------------------------------------

# Lanes are placed by the XDMA IP (GTY Quad 225); only PERST# needs a pin here.
set_property -dict {PACKAGE_PIN A9 IOSTANDARD LVCMOS18} [get_ports pcie_perstn]
set_false_path -from [get_ports pcie_perstn]

# ---------------------------------------------------------------------------
# SFP 1
# ---------------------------------------------------------------------------

set_property PACKAGE_PIN A4 [get_ports sfp_1_rxp]
set_property PACKAGE_PIN A3 [get_ports sfp_1_rxn]
set_property PACKAGE_PIN B7 [get_ports sfp_1_txp]
set_property PACKAGE_PIN B6 [get_ports sfp_1_txn]

set_property -dict {PACKAGE_PIN D14 IOSTANDARD LVCMOS18} [get_ports sfp_1_mod_def_0]
set_property -dict {PACKAGE_PIN B14 IOSTANDARD LVCMOS18} [get_ports sfp_1_tx_fault]
set_property -dict {PACKAGE_PIN D13 IOSTANDARD LVCMOS18} [get_ports sfp_1_los]
set_false_path -from [get_ports {sfp_1_mod_def_0 sfp_1_tx_fault sfp_1_los}]

# ---------------------------------------------------------------------------
# LEDs
# ---------------------------------------------------------------------------

# sfp_1_led: 25G link locked, led_g: PCIe link up
set_property -dict {PACKAGE_PIN B12 IOSTANDARD LVCMOS18 DRIVE 8 SLEW SLOW} [get_ports sfp_1_led]
set_property -dict {PACKAGE_PIN A12 IOSTANDARD LVCMOS18 DRIVE 8 SLEW SLOW} [get_ports led_g]
set_false_path -to [get_ports {sfp_1_led led_g}]

# ---------------------------------------------------------------------------
# RX lock watchdog
# ---------------------------------------------------------------------------

# rx_lock_watchdog resynchronizes rx_locked and rx_reset_done onto freerun_clk.
set_false_path -to [get_cells -hierarchical -filter {NAME =~ *status_sync_inst/data_shift_reg_q_reg*}]
set_property ASYNC_REG TRUE [get_cells -hierarchical -filter {NAME =~ *status_sync_inst/data_shift_reg_q_reg*}]

# ---------------------------------------------------------------------------
# Debug (DEBUG_EN = 1)
# ---------------------------------------------------------------------------

# vio_ctrl runs on freerun_clk. Its inputs are status and counters from the GT
# and AXI domains, and its outputs are static controls (rx_invert is
# resynchronized, loopback_in is asynchronous), so neither side is timed.
set_false_path -quiet -to   [get_cells -quiet -hierarchical -filter {NAME =~ *vio_ctrl_inst*}]
set_false_path -quiet -from [get_cells -quiet -hierarchical -filter {NAME =~ *vio_ctrl_inst*}]
set_property ASYNC_REG TRUE [get_cells -quiet -hierarchical -filter {NAME =~ *rx_invert_sync_inst/data_shift_reg_q_reg*}]

# Clock the debug hub from the always-running 100 MHz clock, so the VIO stays
# reachable even when the GT user clocks are down.
set_property C_CLK_INPUT_FREQ_HZ 100000000 [get_debug_cores -quiet dbg_hub]
set_property C_ENABLE_CLK_DIVIDER false [get_debug_cores -quiet dbg_hub]
connect_debug_port -quiet dbg_hub/clk [get_nets -quiet freerun_clk]

# ---------------------------------------------------------------------------
# Configuration
# ---------------------------------------------------------------------------

set_property BITSTREAM.CONFIG.SPI_BUSWIDTH 4 [current_design]
