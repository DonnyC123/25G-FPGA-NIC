# Hardware Manager helpers for the nic_top debug cores (DEBUG_EN = 1).
#
# After programming the FPGA (with the .ltx probes file loaded):
#   source /share/25G-FPGA-NIC/top/scripts/debug_rx.tcl
#   rx_status                 ;# GT/link status and RX drop counters
#   rx_invert 1               ;# invert RX polarity (0 = normal)
#   loopback 2                ;# 0 normal, 1 near-end PCS, 2 near-end PMA,
#                             ;# 4 far-end PMA, 6 far-end PCS
#   rx_reset                  ;# pulse the GT RX datapath reset
#   rx_capture                ;# capture ila_rx when a decoded word arrives
#   rx_raw_capture            ;# capture ila_rx right away (raw GT data, slips)
#   c2h_capture               ;# capture ila_c2h when C2H tvalid rises
#   h2c_capture               ;# capture ila_c2h when H2C tvalid rises
#
# Captures are saved as CSV under debug/ in the repo.
#
# Probes are found by net name pattern, since synthesis can add suffixes
# (rx_locked_1, pcs_stream[valid]_orig, sfp_1_los_IBUF).

set ::dbg_out_dir [file normalize [file join [file dirname [info script]] .. debug]]

proc dbg_core {kind name} {
  set core [get_hw_${kind}s -quiet -of_objects [current_hw_device] -filter "CELL_NAME =~ *${name}_inst*"]
  if {$core eq ""} {
    error "No $name found. Program the device with the debug build and load its .ltx file."
  }
  return $core
}

proc dbg_probe {core pattern} {
  set probe [get_hw_probes -quiet -of_objects $core -filter "NAME =~ \"$pattern\""]
  if {[llength $probe] != 1} {
    error "Expected one probe matching '$pattern' on $core, found [llength $probe].\
           Probes: [get_hw_probes -of_objects $core]"
  }
  return $probe
}

proc vio_set {pattern value} {
  set vio [dbg_core vio vio_ctrl]
  set probe [dbg_probe $vio $pattern]
  set_property OUTPUT_VALUE_RADIX UNSIGNED $probe
  set_property OUTPUT_VALUE $value $probe
  commit_hw_vio $probe
}

proc rx_invert {on} {
  vio_set *rx_invert* $on
  puts "rx_invert = $on"
}

proc loopback {mode} {
  vio_set *loopback_mode* $mode
  # The GT samples loopback_in on its own; reset RX so it relocks in the new mode.
  rx_reset
  puts "loopback_mode = $mode"
}

proc rx_reset {} {
  vio_set *rx_datapath_rst* 1
  after 10
  vio_set *rx_datapath_rst* 0
  puts "GT RX datapath reset pulsed"
}

proc rx_status {} {
  set vio [dbg_core vio vio_ctrl]
  refresh_hw_vio $vio
  set inputs {
    gt_powergood tx_reset_done rx_reset_done rx_cdr_stable rx_userclk_active
    rx_locked pcie_link_up sfp_1_los sfp_1_tx_fault sfp_1_mod_def_0
    overflow_drops crc_drops pcs_drops
  }
  set outputs {loopback_mode rx_invert rx_datapath_rst}
  foreach name [concat $inputs $outputs] {
    set probe [dbg_probe $vio *${name}*]
    if {$name in $inputs} {
      set_property INPUT_VALUE_RADIX UNSIGNED $probe
      set value [get_property INPUT_VALUE $probe]
    } else {
      set value [get_property OUTPUT_VALUE $probe]
    }
    puts [format "  %-18s %s" $name $value]
  }
}

# Triggers when one probe of an ILA matches compare (eq1'b1 = goes high,
# eq1'bX = right away) and saves the capture as debug/<file>.
proc ila_capture {name pattern compare file} {
  set ila [dbg_core ila $name]
  file mkdir $::dbg_out_dir
  set file [file join $::dbg_out_dir $file]
  reset_hw_ila $ila
  set_property CONTROL.TRIGGER_POSITION 512 $ila
  set_property TRIGGER_COMPARE_VALUE $compare [dbg_probe $ila $pattern]
  run_hw_ila $ila
  puts "Armed $name on $pattern; waiting up to 10 s"
  if {[catch {wait_on_hw_ila -timeout 0.17 $ila}]} {
    puts "$name did not trigger"
    return
  }
  set data [upload_hw_ila_data $ila]
  display_hw_ila_data $data
  write_hw_ila_data -csv_file -force $file $data
  puts "Saved $file"
}

proc rx_capture {} {
  # The decoded stream's valid: a frame word came out of the PCS.
  ila_capture ila_rx *pcs_stream?valid* eq1'b1 ila_rx.csv
}

proc rx_raw_capture {} {
  # Triggers immediately: a snapshot of raw GT data and bitslip activity.
  ila_capture ila_rx *rx_bitslip* eq1'bX ila_rx_raw.csv
}

proc c2h_capture {} {
  # C2H tvalid: rx_top offered data to the XDMA.
  ila_capture ila_c2h *rx_axi_stream*valid* eq1'b1 ila_c2h.csv
}

proc h2c_capture {} {
  # H2C tvalid: the XDMA offered a TX frame. ila_c2h shares this clock, so
  # the capture shows H2C tready and tlast.
  ila_capture ila_c2h *tx_axi_stream*valid* eq1'b1 ila_h2c.csv
}
