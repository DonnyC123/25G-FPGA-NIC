# Creates the debug cores nic_top instantiates when DEBUG_EN = 1:
#   vio_ctrl  (freerun_clk) - GT/link status and drop counters in; loopback,
#                             RX polarity and RX datapath reset out
#   ila_rx    (rx_usrclk)   - raw GT RX data, lock, decoded stream, drops
#   ila_c2h   (axi_aclk)    - the C2H and H2C AXI-Stream handshakes
#
# Probe widths must match the instances in nic_top.sv.
#
# Run from the Tcl console with the nic project open:
#   source /share/25G-FPGA-NIC/top/scripts/create_debug_ip.tcl

# Re-running replaces the IP created by a previous run of this script.
proc remove_existing_ip {ip_name} {
  if {[get_ips -quiet $ip_name] eq ""} {
    return
  }
  set xci [get_files $ip_name.xci]
  set ip_dir [file dirname $xci]
  puts "Removing existing $ip_name ($xci)"
  export_ip_user_files -of_objects $xci -no_script -reset -force -quiet
  remove_files $xci
  file delete -force $ip_dir
}

proc finish_ip {ip_name} {
  generate_target all [get_files $ip_name.xci]
  create_ip_run [get_files $ip_name.xci]
  puts "Created $ip_name"
}

proc create_ila {ip_name depth widths} {
  remove_existing_ip $ip_name
  create_ip -name ila -vendor xilinx.com -library ip -module_name $ip_name

  set cfg [list CONFIG.C_NUM_OF_PROBES [llength $widths] CONFIG.C_DATA_DEPTH $depth]
  for {set i 0} {$i < [llength $widths]} {incr i} {
    lappend cfg CONFIG.C_PROBE${i}_WIDTH [lindex $widths $i]
  }
  set_property -dict $cfg [get_ips $ip_name]
  finish_ip $ip_name
}

proc create_vio {ip_name in_widths out_widths} {
  remove_existing_ip $ip_name
  create_ip -name vio -vendor xilinx.com -library ip -module_name $ip_name

  set cfg [list CONFIG.C_NUM_PROBE_IN [llength $in_widths] CONFIG.C_NUM_PROBE_OUT [llength $out_widths]]
  for {set i 0} {$i < [llength $in_widths]} {incr i} {
    lappend cfg CONFIG.C_PROBE_IN${i}_WIDTH [lindex $in_widths $i]
  }
  # Outputs start at 0: normal operation, no inversion, not in reset.
  for {set i 0} {$i < [llength $out_widths]} {incr i} {
    lappend cfg CONFIG.C_PROBE_OUT${i}_WIDTH [lindex $out_widths $i]
    lappend cfg CONFIG.C_PROBE_OUT${i}_INIT_VAL 0x0
  }
  set_property -dict $cfg [get_ips $ip_name]
  finish_ip $ip_name
}

# in:  gt_powergood tx_reset_done rx_reset_done rx_cdr_stable rx_userclk_active
#      rx_locked pcie_link_up sfp_1_los sfp_1_tx_fault sfp_1_mod_def_0
#      overflow_drops crc_drops pcs_drops
# out: loopback_mode rx_invert rx_datapath_rst
create_vio vio_ctrl {1 1 1 1 1 1 1 1 1 1 32 32 32} {3 1 1}

# rx_raw_data rx_eth_rst rx_locked rx_bitslip pcs valid/last/drop pcs data
# crc_drop fifo_cancel
create_ila ila_rx 4096 {64 1 1 1 1 1 1 64 1 1}

# C2H data[63:0] valid ready last, rx_axi_rst, H2C valid ready last
create_ila ila_c2h 2048 {64 1 1 1 1 1 1 1}
