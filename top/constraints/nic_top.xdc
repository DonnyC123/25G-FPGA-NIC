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
# from unrelated oscillators. They only cross through async_packet_fifo and
# async_fifo (gray-coded pointers + 2-flop synchronizers), handshake_cdc (held
# data + synchronized req/ack) and rst_sync, so bound each crossing to one
# destination clock period instead of timing it as synchronous.
# Each SFP port has its own TX and RX user clock (gt0_inst = SFP 1,
# gt1_inst = SFP 2); the two ports never exchange data with each other.
set_max_delay -datapath_only -from [get_clocks axi_aclk] -to [get_clocks -of_objects [get_pins {gt0_inst/gtwiz_userclk_tx_usrclk2_out[0] gt1_inst/gtwiz_userclk_tx_usrclk2_out[0]}]] 2.482
set_max_delay -datapath_only -from [get_clocks -of_objects [get_pins {gt0_inst/gtwiz_userclk_tx_usrclk2_out[0] gt1_inst/gtwiz_userclk_tx_usrclk2_out[0]}]] -to [get_clocks axi_aclk] 4.000
set_max_delay -datapath_only -from [get_clocks axi_aclk] -to [get_clocks -of_objects [get_pins {gt0_inst/gtwiz_userclk_rx_usrclk2_out[0] gt1_inst/gtwiz_userclk_rx_usrclk2_out[0]}]] 2.482
set_max_delay -datapath_only -from [get_clocks -of_objects [get_pins {gt0_inst/gtwiz_userclk_rx_usrclk2_out[0] gt1_inst/gtwiz_userclk_rx_usrclk2_out[0]}]] -to [get_clocks axi_aclk] 4.000

# The async FIFO pointer synchronizers need ASYNC_REG so their two flops are
# placed together, and the gray-coded pointer bits must not skew by more than
# one period of the fastest clock or the receiver can see a mixed value.
set_property ASYNC_REG TRUE [get_cells -hierarchical -filter {NAME =~ *_addr_sync_inst/data_shift_reg_q_reg*}]
set_property ASYNC_REG TRUE [get_cells -hierarchical -filter {NAME =~ *handshake_cdc_inst/req_sync_inst/data_shift_reg_q_reg* || NAME =~ *handshake_cdc_inst/ack_sync_inst/data_shift_reg_q_reg*}]
set_bus_skew -from [get_cells {g_port[0].tx_top_inst/tx_fifo_ctrl_inst/async_packet_fifo_inst/commit_addr_gray_q_reg[*]}] -to [get_cells {g_port[0].tx_top_inst/tx_fifo_ctrl_inst/async_packet_fifo_inst/commit_addr_sync_inst/data_shift_reg_q_reg[0][*]}] 2.482
set_bus_skew -from [get_cells {g_port[0].tx_top_inst/tx_fifo_ctrl_inst/async_packet_fifo_inst/rd_addr_gray_q_reg[*]}] -to [get_cells {g_port[0].tx_top_inst/tx_fifo_ctrl_inst/async_packet_fifo_inst/rd_addr_sync_inst/data_shift_reg_q_reg[0][*]}] 2.482
set_bus_skew -from [get_cells {g_port[0].tx_top_inst/csum_fifo_inst/wr_addr_gray_q_reg[*]}] -to [get_cells {g_port[0].tx_top_inst/csum_fifo_inst/wr_addr_sync_inst/data_shift_reg_q_reg[0][*]}] 2.482
set_bus_skew -from [get_cells {g_port[0].tx_top_inst/csum_fifo_inst/rd_addr_gray_q_reg[*]}] -to [get_cells {g_port[0].tx_top_inst/csum_fifo_inst/rd_addr_sync_inst/data_shift_reg_q_reg[0][*]}] 2.482
set_bus_skew -from [get_cells {g_port[0].rx_top_inst/rx_fifo_ctrl_inst/async_packet_fifo_inst/commit_addr_gray_q_reg[*]}] -to [get_cells {g_port[0].rx_top_inst/rx_fifo_ctrl_inst/async_packet_fifo_inst/commit_addr_sync_inst/data_shift_reg_q_reg[0][*]}] 2.482
set_bus_skew -from [get_cells {g_port[0].rx_top_inst/rx_fifo_ctrl_inst/async_packet_fifo_inst/rd_addr_gray_q_reg[*]}] -to [get_cells {g_port[0].rx_top_inst/rx_fifo_ctrl_inst/async_packet_fifo_inst/rd_addr_sync_inst/data_shift_reg_q_reg[0][*]}] 2.482
set_bus_skew -from [get_cells {g_port[0].rx_top_inst/rx_fifo_ctrl_inst/meta_fifo_inst/wr_addr_gray_q_reg[*]}] -to [get_cells {g_port[0].rx_top_inst/rx_fifo_ctrl_inst/meta_fifo_inst/wr_addr_sync_inst/data_shift_reg_q_reg[0][*]}] 2.482
set_bus_skew -from [get_cells {g_port[0].rx_top_inst/rx_fifo_ctrl_inst/meta_fifo_inst/rd_addr_gray_q_reg[*]}] -to [get_cells {g_port[0].rx_top_inst/rx_fifo_ctrl_inst/meta_fifo_inst/rd_addr_sync_inst/data_shift_reg_q_reg[0][*]}] 2.482
set_bus_skew -from [get_cells {g_port[1].tx_top_inst/tx_fifo_ctrl_inst/async_packet_fifo_inst/commit_addr_gray_q_reg[*]}] -to [get_cells {g_port[1].tx_top_inst/tx_fifo_ctrl_inst/async_packet_fifo_inst/commit_addr_sync_inst/data_shift_reg_q_reg[0][*]}] 2.482
set_bus_skew -from [get_cells {g_port[1].tx_top_inst/tx_fifo_ctrl_inst/async_packet_fifo_inst/rd_addr_gray_q_reg[*]}] -to [get_cells {g_port[1].tx_top_inst/tx_fifo_ctrl_inst/async_packet_fifo_inst/rd_addr_sync_inst/data_shift_reg_q_reg[0][*]}] 2.482
set_bus_skew -from [get_cells {g_port[1].tx_top_inst/csum_fifo_inst/wr_addr_gray_q_reg[*]}] -to [get_cells {g_port[1].tx_top_inst/csum_fifo_inst/wr_addr_sync_inst/data_shift_reg_q_reg[0][*]}] 2.482
set_bus_skew -from [get_cells {g_port[1].tx_top_inst/csum_fifo_inst/rd_addr_gray_q_reg[*]}] -to [get_cells {g_port[1].tx_top_inst/csum_fifo_inst/rd_addr_sync_inst/data_shift_reg_q_reg[0][*]}] 2.482
set_bus_skew -from [get_cells {g_port[1].rx_top_inst/rx_fifo_ctrl_inst/async_packet_fifo_inst/commit_addr_gray_q_reg[*]}] -to [get_cells {g_port[1].rx_top_inst/rx_fifo_ctrl_inst/async_packet_fifo_inst/commit_addr_sync_inst/data_shift_reg_q_reg[0][*]}] 2.482
set_bus_skew -from [get_cells {g_port[1].rx_top_inst/rx_fifo_ctrl_inst/async_packet_fifo_inst/rd_addr_gray_q_reg[*]}] -to [get_cells {g_port[1].rx_top_inst/rx_fifo_ctrl_inst/async_packet_fifo_inst/rd_addr_sync_inst/data_shift_reg_q_reg[0][*]}] 2.482
set_bus_skew -from [get_cells {g_port[1].rx_top_inst/rx_fifo_ctrl_inst/meta_fifo_inst/wr_addr_gray_q_reg[*]}] -to [get_cells {g_port[1].rx_top_inst/rx_fifo_ctrl_inst/meta_fifo_inst/wr_addr_sync_inst/data_shift_reg_q_reg[0][*]}] 2.482
set_bus_skew -from [get_cells {g_port[1].rx_top_inst/rx_fifo_ctrl_inst/meta_fifo_inst/rd_addr_gray_q_reg[*]}] -to [get_cells {g_port[1].rx_top_inst/rx_fifo_ctrl_inst/meta_fifo_inst/rd_addr_sync_inst/data_shift_reg_q_reg[0][*]}] 2.482

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
# SFP 2 (GTYE4_CHANNEL_X0Y14, same quad and QPLL0 as SFP 1)
# ---------------------------------------------------------------------------

set_property PACKAGE_PIN B2 [get_ports sfp_2_rxp]
set_property PACKAGE_PIN B1 [get_ports sfp_2_rxn]
set_property PACKAGE_PIN D7 [get_ports sfp_2_txp]
set_property PACKAGE_PIN D6 [get_ports sfp_2_txn]

set_property -dict {PACKAGE_PIN E11 IOSTANDARD LVCMOS18} [get_ports sfp_2_mod_def_0]
set_property -dict {PACKAGE_PIN F9  IOSTANDARD LVCMOS18} [get_ports sfp_2_tx_fault]
set_property -dict {PACKAGE_PIN E10 IOSTANDARD LVCMOS18} [get_ports sfp_2_los]
set_false_path -from [get_ports {sfp_2_mod_def_0 sfp_2_tx_fault sfp_2_los}]

# ---------------------------------------------------------------------------
# LEDs
# ---------------------------------------------------------------------------

# sfp_1_led / sfp_2_led: 25G link locked on that port, led_g: PCIe link up
set_property -dict {PACKAGE_PIN B12 IOSTANDARD LVCMOS18 DRIVE 8 SLEW SLOW} [get_ports sfp_1_led]
set_property -dict {PACKAGE_PIN C12 IOSTANDARD LVCMOS18 DRIVE 8 SLEW SLOW} [get_ports sfp_2_led]
set_property -dict {PACKAGE_PIN A12 IOSTANDARD LVCMOS18 DRIVE 8 SLEW SLOW} [get_ports led_g]
set_false_path -to [get_ports {sfp_1_led sfp_2_led led_g}]

# ---------------------------------------------------------------------------
# RX lock watchdog
# ---------------------------------------------------------------------------

# rx_lock_watchdog resynchronizes rx_locked and rx_reset_done onto freerun_clk.
set_false_path -to [get_cells -hierarchical -filter {NAME =~ *status_sync_inst/data_shift_reg_q_reg*}]
set_property ASYNC_REG TRUE [get_cells -hierarchical -filter {NAME =~ *status_sync_inst/data_shift_reg_q_reg*}]

# The link resets combine GT status from other clocks; link_rst_sync_inst
# registers them on freerun_clk so rst_sync's async preset is driven by a flop.
set_false_path -to [get_cells -hierarchical -filter {NAME =~ *link_rst_sync_inst/data_shift_reg_q_reg*}]
set_property ASYNC_REG TRUE [get_cells -hierarchical -filter {NAME =~ *link_rst_sync_inst/data_shift_reg_q_reg*}]
set_false_path -to [get_pins -of_objects [get_cells -hierarchical -filter {NAME =~ *rst_sync_inst/sync_q_reg*}] -filter {REF_PIN_NAME == PRE}]

# ---------------------------------------------------------------------------
# Debug hub
# ---------------------------------------------------------------------------

# The block design still has jtag_axi_0 and system_ila_0. Clock the debug hub
# from the always-running 100 MHz clock so they stay reachable even when the
# GT user clocks are down.
set_property C_CLK_INPUT_FREQ_HZ 100000000 [get_debug_cores -quiet dbg_hub]
set_property C_ENABLE_CLK_DIVIDER false [get_debug_cores -quiet dbg_hub]
connect_debug_port -quiet dbg_hub/clk [get_nets -quiet freerun_clk]

# ---------------------------------------------------------------------------
# Configuration
# ---------------------------------------------------------------------------

set_property BITSTREAM.CONFIG.SPI_BUSWIDTH 4 [current_design]
