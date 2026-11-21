# Creates the two GT wizards for nic_top, one GTY channel per SFP port,
# 25.78125 Gb/s raw 64-bit from the 156.25 MHz MGTREFCLK0_227:
#   gtwizard_ultrascale_0  SFP 1 on X0Y15, owns the quad's GTYE4_COMMON (QPLL0)
#   gtwizard_ultrascale_1  SFP 2 on X0Y14, uses QPLL0 from gtwizard_ultrascale_0
#
# Both channels sit in Quad 227, which has a single COMMON, so only the first
# IP builds it. It exports qpll0outclk/qpll0outrefclk/qpll0lock, and the second
# IP (LOCATE_COMMON = EXAMPLE_DESIGN) takes them in. Each IP keeps its own
# reset controller and user clocking, so each port has its own TX/RX clocks.
#
# Run from the Tcl console with the nic project open:
#   source /share/25G-FPGA-NIC/top/scripts/create_gtwizard.tcl

proc create_gt {ip_name rx_pin gt_chan locate_common optional_ports} {
  # Check that the SFP RX pin really belongs to the channel we are about to use.
  set site [get_sites -quiet -of_objects [get_package_pins -quiet $rx_pin]]
  if {$site ne "" && ![string match "*_${gt_chan}" $site]} {
    error "Pin $rx_pin is on $site, not GTYE4_CHANNEL_${gt_chan}. Update gt_chan in this script."
  }

  # Re-running replaces the IP created by a previous run of this script.
  if {[get_ips -quiet $ip_name] ne ""} {
    set xci [get_files $ip_name.xci]
    set ip_dir [file dirname $xci]
    puts "Removing existing $ip_name ($xci)"
    export_ip_user_files -of_objects $xci -no_script -reset -force -quiet
    remove_files $xci
    file delete -force $ip_dir
  }

  create_ip -name gtwizard_ultrascale -vendor xilinx.com -library ip -module_name $ip_name
  set ip [get_ips $ip_name]

  # 25.78125 Gb/s from 156.25 MHz needs QPLL0 N = 82.5, so fractional-N is
  # required (integer-N only offers 161.13 / 322.27 / 644.53 MHz).
  # Fraction 0.5 => numerator 0.5 * 2^24 = 8388608.
  set frac_params [list_property $ip CONFIG.*FRACN*]
  puts "Fractional-N parameters on this IP: $frac_params"
  if {[llength $frac_params] == 0} {
    error "No fractional-N parameters found. Set the refclk to 156.25 in the IP GUI instead."
  }

  set_property -dict [list \
    CONFIG.CHANNEL_ENABLE           $gt_chan \
    CONFIG.TX_MASTER_CHANNEL        $gt_chan \
    CONFIG.RX_MASTER_CHANNEL        $gt_chan \
    CONFIG.TX_PLL_TYPE              {QPLL0} \
    CONFIG.RX_PLL_TYPE              {QPLL0} \
    CONFIG.TX_LINE_RATE             {25.78125} \
    CONFIG.RX_LINE_RATE             {25.78125} \
    CONFIG.TX_QPLL_FRACN_NUMERATOR  {8388608} \
    CONFIG.RX_QPLL_FRACN_NUMERATOR  {8388608} \
  ] $ip

  set_property -dict [list \
    CONFIG.TX_REFCLK_FREQUENCY      {156.25} \
    CONFIG.RX_REFCLK_FREQUENCY      {156.25} \
    CONFIG.TX_REFCLK_SOURCE         "$gt_chan clk0" \
    CONFIG.RX_REFCLK_SOURCE         "$gt_chan clk0" \
    CONFIG.TX_DATA_ENCODING         {RAW} \
    CONFIG.RX_DATA_DECODING         {RAW} \
    CONFIG.TX_USER_DATA_WIDTH       {64} \
    CONFIG.TX_INT_DATA_WIDTH        {64} \
    CONFIG.RX_USER_DATA_WIDTH       {64} \
    CONFIG.RX_INT_DATA_WIDTH        {64} \
    CONFIG.RX_SLIDE_MODE            {PMA} \
    CONFIG.RX_COMMA_ALIGN_WORD      {1} \
    CONFIG.FREERUN_FREQUENCY        {100} \
    CONFIG.LOCATE_TX_USER_CLOCKING  {CORE} \
    CONFIG.LOCATE_RX_USER_CLOCKING  {CORE} \
    CONFIG.LOCATE_RESET_CONTROLLER  {CORE} \
    CONFIG.LOCATE_COMMON            $locate_common \
    CONFIG.ENABLE_OPTIONAL_PORTS    $optional_ports \
  ] $ip

  generate_target all [get_files $ip_name.xci]
  create_ip_run [get_files $ip_name.xci]

  puts "Created $ip_name on GTYE4_CHANNEL_${gt_chan}"
}

create_gt gtwizard_ultrascale_0 A4 X0Y15 CORE \
  {loopback_in rxslide_in rxpmaresetdone_out txpmaresetdone_out qpll0lock_out qpll0outclk_out qpll0outrefclk_out}

create_gt gtwizard_ultrascale_1 B2 X0Y14 EXAMPLE_DESIGN \
  {loopback_in rxslide_in rxpmaresetdone_out txpmaresetdone_out}
