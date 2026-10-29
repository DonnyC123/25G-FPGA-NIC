module nic_top #(
  parameter int SCRAMBLER_BYPASS = 0
) (
  input  logic       diff_100mhz_clk_p,
  input  logic       diff_100mhz_clk_n,

  input  logic       sfp_mgt_clk_p,
  input  logic       sfp_mgt_clk_n,

  input  logic       sfp_1_rxp,
  input  logic       sfp_1_rxn,
  output logic       sfp_1_txp,
  output logic       sfp_1_txn,

  input  logic       sfp_1_mod_def_0,
  input  logic       sfp_1_tx_fault,
  input  logic       sfp_1_los,
  output logic       sfp_1_led,

  input  logic [7:0] pci_express_x8_rxn,
  input  logic [7:0] pci_express_x8_rxp,
  output logic [7:0] pci_express_x8_txn,
  output logic [7:0] pci_express_x8_txp,
  input  logic       pcie_perstn,
  input  logic       pcie_refclk_clk_p,
  input  logic       pcie_refclk_clk_n,

  output logic [3:0] gpio_led
);

  localparam int AXI_DATA_W = 256;
  localparam int GT_DATA_W  = 64;
  localparam int DEBUG_W    = 8;

  axi_stream_if #(.DATA_W(AXI_DATA_W)) rx_axi_stream ();
  axi_stream_if #(.DATA_W(AXI_DATA_W)) tx_axi_stream ();

  logic                 freerun_clk;
  logic                 mgtrefclk_227;

  logic [7:0]           por_count_d;
  logic [7:0]           por_count_q = '0;
  logic                 freerun_rst_d;
  logic                 freerun_rst_q = 1'b1;

  logic                 axi_aclk;
  logic                 axi_aresetn;
  logic                 axi_rst;

  logic                 tx_usrclk;
  logic                 rx_usrclk;
  logic                 tx_userclk_active;
  logic                 rx_userclk_active;
  logic                 gt_powergood;
  logic                 tx_reset_done;
  logic                 rx_reset_done;
  logic                 rx_cdr_stable;
  logic [2:0]           loopback_mode;

  logic [GT_DATA_W-1:0] gt_tx_data;
  logic [GT_DATA_W-1:0] gt_rx_data;
  logic                 rx_locked;
  logic                 rx_bitslip;

  logic                 rx_ready;
  logic                 tx_ready;
  logic                 rx_link_rst;
  logic                 tx_link_rst;
  logic                 rx_eth_rst;
  logic                 rx_axi_rst;
  logic                 tx_eth_rst;
  logic                 tx_axi_rst;

  logic [DEBUG_W-1:0]   bad_count_dbg;
  logic [15:0]          unlock_count_d;
  logic [15:0]          unlock_count_q;
  logic                 rx_locked_q;

  IBUFDS sysclk_buf_inst (
      .I (diff_100mhz_clk_p),
      .IB(diff_100mhz_clk_n),
      .O (freerun_clk)
  );

  IBUFDS_GTE4 #(
      .REFCLK_EN_TX_PATH (1'b0),
      .REFCLK_HROW_CK_SEL(2'b00),
      .REFCLK_ICNTL_RX   (2'b00)
  ) mgtrefclk_buf_inst (
      .I    (sfp_mgt_clk_p),
      .IB   (sfp_mgt_clk_n),
      .CEB  (1'b0),
      .O    (mgtrefclk_227),
      .ODIV2()
  );

  always_comb begin
    por_count_d   = por_count_q;
    freerun_rst_d = 1'b0;
    if (por_count_q != '1) begin
      por_count_d   = por_count_q + 1'b1;
      freerun_rst_d = 1'b1;
    end
  end

  always_ff @(posedge freerun_clk) begin
    por_count_q   <= por_count_d;
    freerun_rst_q <= freerun_rst_d;
  end

`ifdef SIM_NO_PCIE
  assign axi_aclk            = freerun_clk;
  assign axi_aresetn         = !freerun_rst_q;
  assign pci_express_x8_txn  = '0;
  assign pci_express_x8_txp  = '0;
  assign tx_axi_stream.data  = '0;
  assign tx_axi_stream.mask  = '0;
  assign tx_axi_stream.valid = 1'b0;
  assign tx_axi_stream.last  = 1'b0;
  assign rx_axi_stream.ready = 1'b1;
`else
  design_1_wrapper design_1_wrapper_inst (
      .pci_express_x8_rxn   (pci_express_x8_rxn),
      .pci_express_x8_rxp   (pci_express_x8_rxp),
      .pci_express_x8_txn   (pci_express_x8_txn),
      .pci_express_x8_txp   (pci_express_x8_txp),
      .pcie_perstn          (pcie_perstn),
      .pcie_refclk_clk_n    (pcie_refclk_clk_n),
      .pcie_refclk_clk_p    (pcie_refclk_clk_p),
      .axi_aclk             (axi_aclk),
      .axi_aresetn          (axi_aresetn),
      .M_AXIS_H2C_0_0_tdata (tx_axi_stream.data),
      .M_AXIS_H2C_0_0_tkeep (tx_axi_stream.mask),
      .M_AXIS_H2C_0_0_tvalid(tx_axi_stream.valid),
      .M_AXIS_H2C_0_0_tlast (tx_axi_stream.last),
      .M_AXIS_H2C_0_0_tready(tx_axi_stream.ready),
      .S_AXIS_C2H_0_0_tdata (rx_axi_stream.data),
      .S_AXIS_C2H_0_0_tkeep (rx_axi_stream.mask),
      .S_AXIS_C2H_0_0_tvalid(rx_axi_stream.valid),
      .S_AXIS_C2H_0_0_tlast (rx_axi_stream.last),
      .S_AXIS_C2H_0_0_tready(rx_axi_stream.ready)
  );
`endif

  gtwizard_ultrascale_0 gt_inst (
      .gtwiz_reset_clk_freerun_in        (freerun_clk),
      .gtwiz_reset_all_in                (freerun_rst_q),
      .gtwiz_reset_tx_pll_and_datapath_in(1'b0),
      .gtwiz_reset_tx_datapath_in        (1'b0),
      .gtwiz_reset_rx_pll_and_datapath_in(1'b0),
      .gtwiz_reset_rx_datapath_in        (1'b0),
      .gtwiz_userclk_tx_reset_in         (freerun_rst_q),
      .gtwiz_userclk_rx_reset_in         (freerun_rst_q),
      .gtwiz_userclk_tx_srcclk_out       (),
      .gtwiz_userclk_tx_usrclk_out       (),
      .gtwiz_userclk_tx_usrclk2_out      (tx_usrclk),
      .gtwiz_userclk_tx_active_out       (tx_userclk_active),
      .gtwiz_userclk_rx_srcclk_out       (),
      .gtwiz_userclk_rx_usrclk_out       (),
      .gtwiz_userclk_rx_usrclk2_out      (rx_usrclk),
      .gtwiz_userclk_rx_active_out       (rx_userclk_active),
      .gtrefclk00_in                     (mgtrefclk_227),
      .gtyrxp_in                         (sfp_1_rxp),
      .gtyrxn_in                         (sfp_1_rxn),
      .gtytxp_out                        (sfp_1_txp),
      .gtytxn_out                        (sfp_1_txn),
      .gtwiz_userdata_tx_in              (gt_tx_data),
      .gtwiz_userdata_rx_out             (gt_rx_data),
      .loopback_in                       (loopback_mode),
      .rxslide_in                        (rx_bitslip),
      .gtpowergood_out                   (gt_powergood),
      .gtwiz_reset_tx_done_out           (tx_reset_done),
      .gtwiz_reset_rx_done_out           (rx_reset_done),
      .gtwiz_reset_rx_cdr_stable_out     (rx_cdr_stable),
      .rxpmaresetdone_out                (),
      .txpmaresetdone_out                (),
      .qpll0outclk_out                   (),
      .qpll0outrefclk_out                ()
  );

  always_comb begin
    rx_ready    = rx_reset_done && rx_userclk_active && gt_powergood;
    tx_ready    = tx_reset_done && tx_userclk_active && gt_powergood;
    rx_link_rst = !rx_ready || axi_rst;
    tx_link_rst = !tx_ready || axi_rst;
  end

  rst_sync rx_eth_rst_sync_inst (
      .clk  (rx_usrclk),
      .rst_i(rx_link_rst),
      .rst_o(rx_eth_rst)
  );

  rst_sync rx_axi_rst_sync_inst (
      .clk  (axi_aclk),
      .rst_i(rx_link_rst),
      .rst_o(rx_axi_rst)
  );

  rst_sync tx_eth_rst_sync_inst (
      .clk  (tx_usrclk),
      .rst_i(tx_link_rst),
      .rst_o(tx_eth_rst)
  );

  rst_sync tx_axi_rst_sync_inst (
      .clk  (axi_aclk),
      .rst_i(tx_link_rst),
      .rst_o(tx_axi_rst)
  );

  rx_top #(
      .DIN_W       (GT_DATA_W),
      .GOOD_COUNT  (64),
      .BAD_COUNT   (8),
      .BITSLIP_WAIT(256),
      .FIFO_DEPTH  (512)
  ) rx_top_inst (
      .eth_clk         (rx_usrclk),
      .eth_rst         (rx_eth_rst),
      .axi_clk         (axi_aclk),
      .axi_rst         (rx_axi_rst),
      .raw_data_i      (gt_rx_data),
      .raw_valid_i     (1'b1),
      .locked_o        (rx_locked),
      .bitslip_o       (rx_bitslip),
      .overflow_drops_o(),
      .crc_drops_o     (),
      .pcs_drops_o     (),
      .m_axi           (rx_axi_stream)
  );

  tx_top #(
      .FIFO_DEPTH      (128),
      .SCRAMBLER_BYPASS(SCRAMBLER_BYPASS)
  ) tx_top_inst (
      .axi_clk    (axi_aclk),
      .axi_rst    (tx_axi_rst),
      .eth_clk    (tx_usrclk),
      .eth_rst    (tx_eth_rst),
      .s_axi      (tx_axi_stream),
      .raw_data_o (gt_tx_data),
      .raw_valid_o()
  );

  always_comb begin
    unlock_count_d = unlock_count_q;
    if (rx_locked_q && !rx_locked) begin
      unlock_count_d = unlock_count_q + 1'b1;
    end
  end

  always_ff @(posedge rx_usrclk) begin
    if (rx_eth_rst) begin
      unlock_count_q <= '0;
      rx_locked_q    <= 1'b0;
    end else begin
      unlock_count_q <= unlock_count_d;
      rx_locked_q    <= rx_locked;
    end
  end

  ila_rx ila_rx_inst (
      .clk    (rx_usrclk),
      .probe0 (rx_top_inst.rx_pcs_inst.pcs_decoder_inst.valid_i),
      .probe1 (rx_top_inst.rx_pcs_inst.pcs_decoder_inst.pcs_block_i.sync),
      .probe2 (rx_top_inst.rx_pcs_inst.pcs_decoder_inst.pcs_block_i.payload.block_type),
      .probe3 (rx_top_inst.rx_pcs_inst.pcs_decoder_inst.pcs_block_i.payload),
      .probe4 (rx_top_inst.rx_pcs_inst.pcs_decoder_inst.eth_stream_o.valid),
      .probe5 (rx_top_inst.rx_pcs_inst.pcs_decoder_inst.eth_stream_o.last_bytes),
      .probe6 (rx_top_inst.rx_pcs_inst.pcs_decoder_inst.eth_stream_o.data),
      .probe7 (rx_top_inst.rx_pcs_inst.pcs_decoder_inst.eth_stream_o.last),
      .probe8 (rx_top_inst.rx_pcs_inst.pcs_decoder_inst.eth_stream_o.drop),
      .probe9 (rx_top_inst.rx_pcs_inst.pcs_decoder_inst.pcs_decoder_error_o),
      .probe10(rx_locked),
      .probe11(rx_top_inst.rx_pcs_inst.block_sync_pcs_block),
      .probe12(rx_top_inst.rx_pcs_inst.block_sync_valid)
  );

  ila_axi ila_axi_inst (
      .clk   (axi_aclk),
      .probe0(rx_axi_stream.data),
      .probe1(rx_axi_stream.mask),
      .probe2(rx_axi_stream.valid),
      .probe3(rx_axi_stream.last),
      .probe4(rx_axi_stream.ready)
  );

  ila_tx ila_tx_inst (
      .clk   (tx_usrclk),
      .probe0(gt_tx_data),
      .probe1(tx_top_inst.tx_pcs_inst.tx_framer_inst.out_data_o),
      .probe2(tx_top_inst.tx_pcs_inst.tx_framer_inst.out_control_o),
      .probe3(tx_top_inst.tx_pcs_inst.tx_framer_inst.out_valid_o),
      .probe4(tx_axi_stream.valid),
      .probe5(tx_axi_stream.ready)
  );

  vio_status vio_status_inst (
      .clk       (freerun_clk),
      .probe_in0 (gt_powergood),
      .probe_in1 (tx_reset_done),
      .probe_in2 (rx_reset_done),
      .probe_in3 (rx_locked),
      .probe_in4 (sfp_1_los),
      .probe_in5 (sfp_1_tx_fault),
      .probe_in6 (sfp_1_mod_def_0),
      .probe_in7 (rx_cdr_stable),
      .probe_in8 (bad_count_dbg),
      .probe_in9 (unlock_count_q),
      .probe_out0(loopback_mode)
  );

  assign axi_rst       = !axi_aresetn;
  assign bad_count_dbg = DEBUG_W'(rx_top_inst.rx_pcs_inst.alignment_finder_inst.bad_count_q);
  assign gpio_led      = {rx_locked, rx_reset_done, tx_reset_done, gt_powergood};
  assign sfp_1_led     = !sfp_1_los;

endmodule
