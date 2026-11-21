// XSim behavioral TB: loops each SFP's serial TX back into its RX (like a
// loopback cable) and waits for rx_locked on both ports (sfp_1_led and
// sfp_2_led) to go high. Uses the gtwizard_ultrascale
// behavioral model — exercises real GT bitslip / CDR / reset behavior.
//
// To use:
//   1. In Vivado, add this file to a NEW simulation set (sim_2, etc.) so it
//      doesn't interfere with PCIe/XDMA sim (which needs vendor BFMs).
//      Or keep one sim set and accept that XDMA will boot-loop — we don't
//      care about PCIe for this test.
//   2. Set this file as the simulation top.
//   3. Set sim runtime to at least 50 us (XSim default 1 us is way too short
//      for GT reset + CDR lock + block lock).
//   4. xsim.simulate.runtime: 100us  (in project settings, or via Tcl)

`timescale 1ps/1ps

module nic_top_xsim_tb;

    // 100 MHz freerun (10 ns period = 10000 ps)
    logic diff_100mhz_clk_p = 0;
    logic diff_100mhz_clk_n = 1;
    always #5000 diff_100mhz_clk_p = ~diff_100mhz_clk_p;
    always #5000 diff_100mhz_clk_n = ~diff_100mhz_clk_n;

    // 156.25 MHz GT refclk (6.4 ns period = 6400 ps)
    logic sfp_mgt_clk_p = 0;
    logic sfp_mgt_clk_n = 1;
    always #3200 sfp_mgt_clk_p = ~sfp_mgt_clk_p;
    always #3200 sfp_mgt_clk_n = ~sfp_mgt_clk_n;

    // 100 MHz PCIe refclk — design needs it present even though we ignore PCIe
    logic pcie_refclk_clk_p = 0;
    logic pcie_refclk_clk_n = 1;
    always #5000 pcie_refclk_clk_p = ~pcie_refclk_clk_p;
    always #5000 pcie_refclk_clk_n = ~pcie_refclk_clk_n;

    // SFP serial — external loopback, each port's TX drives its own RX.
    wire  sfp_1_txp;
    wire  sfp_1_txn;
    wire  sfp_1_rxp = sfp_1_txp;
    wire  sfp_1_rxn = sfp_1_txn;

    // SFP control/status pins — module present, no fault, signal good
    logic sfp_1_mod_def_0 = 1'b0;
    logic sfp_1_tx_fault  = 1'b0;
    logic sfp_1_los       = 1'b0;
    wire  sfp_1_led;

    wire  sfp_2_txp;
    wire  sfp_2_txn;
    wire  sfp_2_rxp = sfp_2_txp;
    wire  sfp_2_rxn = sfp_2_txn;

    logic sfp_2_mod_def_0 = 1'b0;
    logic sfp_2_tx_fault  = 1'b0;
    logic sfp_2_los       = 1'b0;
    wire  sfp_2_led;

    // PCIe lanes — tie off RX, leave TX floating
    logic [7:0] pci_express_x8_rxn = 8'hFF;
    logic [7:0] pci_express_x8_rxp = 8'h00;
    wire  [7:0] pci_express_x8_txn;
    wire  [7:0] pci_express_x8_txp;
    logic       pcie_perstn = 1'b0;  // hold PCIe in reset — we don't use it

    wire       led_g;

    nic_top #(
        .SCRAMBLER_BYPASS (0)   // debug: easier to read TX bits on the wire
    ) u_dut (
        .diff_100mhz_clk_p (diff_100mhz_clk_p),
        .diff_100mhz_clk_n (diff_100mhz_clk_n),
        .sfp_mgt_clk_p     (sfp_mgt_clk_p),
        .sfp_mgt_clk_n     (sfp_mgt_clk_n),
        .sfp_1_rxp         (sfp_1_rxp),
        .sfp_1_rxn         (sfp_1_rxn),
        .sfp_1_txp         (sfp_1_txp),
        .sfp_1_txn         (sfp_1_txn),
        .sfp_1_mod_def_0   (sfp_1_mod_def_0),
        .sfp_1_tx_fault    (sfp_1_tx_fault),
        .sfp_1_los         (sfp_1_los),
        .sfp_1_led         (sfp_1_led),
        .sfp_2_rxp         (sfp_2_rxp),
        .sfp_2_rxn         (sfp_2_rxn),
        .sfp_2_txp         (sfp_2_txp),
        .sfp_2_txn         (sfp_2_txn),
        .sfp_2_mod_def_0   (sfp_2_mod_def_0),
        .sfp_2_tx_fault    (sfp_2_tx_fault),
        .sfp_2_los         (sfp_2_los),
        .sfp_2_led         (sfp_2_led),
        .pci_express_x8_rxn(pci_express_x8_rxn),
        .pci_express_x8_rxp(pci_express_x8_rxp),
        .pci_express_x8_txn(pci_express_x8_txn),
        .pci_express_x8_txp(pci_express_x8_txp),
        .pcie_perstn       (pcie_perstn),
        .pcie_refclk_clk_p (pcie_refclk_clk_p),
        .pcie_refclk_clk_n (pcie_refclk_clk_n),
        .led_g             (led_g)
    );

    // sfp_N_led = rx_locked[N-1] (direct, no CDC); wait for both ports.
    wire rx_locked = sfp_1_led && sfp_2_led;

    initial begin
        $display("[%0t] sim start, waiting for rx_locked...", $time);

        // Watch for lock, then run for a long time to confirm it stays locked
        // (alignment_finder will unlock after BAD_COUNT=8 invalid sync headers
        // in a row, so any glitch will show up as rx_locked dropping).
        fork
            begin : timeout
                #500us;
                $display("[%0t] TIMEOUT — rx_locked never asserted", $time);
                $display("  freerun_rst=%b sfp_1_led=%b sfp_2_led=%b",
                         u_dut.freerun_rst_q, sfp_1_led, sfp_2_led);
                $finish;
            end
            begin : success
                @(posedge rx_locked);
                $display("[%0t] rx_locked HIGH — block lock achieved", $time);

                // Hold for a long stretch and watch for any unlock event.
                fork
                    begin : hold
                        #500us;
                        $display("[%0t] sim done — rx_locked stayed high for 500us", $time);
                        $finish;
                    end
                    begin : unlock_watch
                        @(negedge rx_locked);
                        $display("[%0t] FAIL — rx_locked dropped after lock", $time);
                        #1us;
                        $finish;
                    end
                join_any
                disable fork;
            end
        join_any
        disable fork;
    end

    // Optional: dump waves
    initial begin
        $dumpfile("nic_top_xsim_tb.vcd");
        $dumpvars(0, nic_top_xsim_tb);
    end

endmodule
