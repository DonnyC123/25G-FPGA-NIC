# Creates gtwizard_ultrascale_0 for nic_top: one GTY channel on SFP 1,
# 25.78125 Gb/s raw 64-bit, QPLL0 from the 156.25 MHz MGTREFCLK0_227.
#
# Run from the Tcl console with the nic project open:
#   source /share/25G-FPGA-NIC/top/scripts/create_gtwizard.tcl

set ip_name   gtwizard_ultrascale_0
set rx_pin    A4
set gt_chan   X0Y15

# Check that the SFP 1 RX pin really belongs to the channel we are about to use.
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
  CONFIG.LOCATE_COMMON            {CORE} \
  CONFIG.ENABLE_OPTIONAL_PORTS    {loopback_in rxslide_in rxpmaresetdone_out txpmaresetdone_out qpll0outclk_out qpll0outrefclk_out} \
] [get_ips $ip_name]

generate_target all [get_files $ip_name.xci]
create_ip_run [get_files $ip_name.xci]

puts "Created $ip_name on GTYE4_CHANNEL_${gt_chan}"
