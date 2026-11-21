# Gives xdma_1 in design_1 one H2C and one C2H AXI-Stream channel per SFP port
# and makes the new channel ports external, so design_1_wrapper has
# M_AXIS_H2C_1_0 / S_AXIS_C2H_1_0 next to the existing _0_0 ports.
#
# Run from the Tcl console with the nic project open:
#   source /share/25G-FPGA-NIC/top/scripts/xdma_channels.tcl

set num_ports 2

open_bd_design [get_files design_1.bd]

set_property -dict [list \
  CONFIG.xdma_rnum_chnl $num_ports \
  CONFIG.xdma_wnum_chnl $num_ports \
] [get_bd_cells xdma_1]

for {set i 1} {$i < $num_ports} {incr i} {
  if {[get_bd_intf_ports -quiet M_AXIS_H2C_${i}_0] eq ""} {
    make_bd_intf_pins_external [get_bd_intf_pins xdma_1/M_AXIS_H2C_${i}]
  }
  if {[get_bd_intf_ports -quiet S_AXIS_C2H_${i}_0] eq ""} {
    make_bd_intf_pins_external [get_bd_intf_pins xdma_1/S_AXIS_C2H_${i}]
  }
  # External slave ports do not inherit these from xdma_1; match S_AXIS_C2H_0_0.
  set_property -dict [list \
    CONFIG.FREQ_HZ         {250000000} \
    CONFIG.HAS_TKEEP       {1} \
    CONFIG.HAS_TLAST       {1} \
    CONFIG.HAS_TREADY      {1} \
    CONFIG.HAS_TSTRB       {0} \
    CONFIG.TDATA_NUM_BYTES {32} \
    CONFIG.TDEST_WIDTH     {0} \
    CONFIG.TID_WIDTH       {0} \
    CONFIG.TUSER_WIDTH     {0} \
  ] [get_bd_intf_ports S_AXIS_C2H_${i}_0]
}

validate_bd_design
save_bd_design
generate_target all [get_files design_1.bd]
make_wrapper -files [get_files design_1.bd] -top -force

puts "xdma_1 now has $num_ports H2C and $num_ports C2H channels"
