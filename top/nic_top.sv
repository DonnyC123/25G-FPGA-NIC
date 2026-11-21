module nic_top
  import rss_pkg::*;
  import nic_regs_pkg::*;
#(
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

  input  logic       sfp_2_rxp,
  input  logic       sfp_2_rxn,
  output logic       sfp_2_txp,
  output logic       sfp_2_txn,

  input  logic       sfp_2_mod_def_0,
  input  logic       sfp_2_tx_fault,
  input  logic       sfp_2_los,
  output logic       sfp_2_led,

  input  logic [7:0] pci_express_x8_rxn,
  input  logic [7:0] pci_express_x8_rxp,
  output logic [7:0] pci_express_x8_txn,
  output logic [7:0] pci_express_x8_txp,
  input  logic       pcie_perstn,
  input  logic       pcie_refclk_clk_p,
  input  logic       pcie_refclk_clk_n,

  output logic       led_g
);

  localparam int AXI_DATA_W = 256;
  localparam int GT_DATA_W  = 64;
  localparam int DROP_W     = 32;

  axi_stream_if #(.DATA_W(AXI_DATA_W)) rx_axi_stream [NIC_PORTS] ();
  axi_stream_if #(.DATA_W(AXI_DATA_W)) tx_axi_stream [NIC_PORTS] ();
  axi4_lite_if                         nic_axil ();

  logic [NIC_PORTS-1:0][RSS_KEY_W-1:0]                  rss_key;
  logic [NIC_PORTS-1:0]                                 udp_ports_en;
  logic [NIC_PORTS-1:0][RETA_SIZE-1:0][RSS_QUEUE_W-1:0] reta;
  logic [NIC_PORTS-1:0]                                 cfg_eth_rst;

  logic                 freerun_clk;
  logic                 mgtrefclk_227;

  logic [7:0]           por_count_d;
  logic [7:0]           por_count_q = '0;
  logic                 freerun_rst_d;
  logic                 freerun_rst_q = 1'b1;

  logic                 axi_aclk;
  logic                 axi_aresetn;
  logic                 axi_rst;
  logic                 pcie_link_up;

  logic                 qpll0_clk;
  logic                 qpll0_refclk;
  logic                 qpll0_lock;

  logic [NIC_PORTS-1:0]                 tx_usrclk;
  logic [NIC_PORTS-1:0]                 rx_usrclk;
  logic [NIC_PORTS-1:0]                 tx_userclk_active;
  logic [NIC_PORTS-1:0]                 rx_userclk_active;
  logic [NIC_PORTS-1:0]                 gt_powergood;
  logic [NIC_PORTS-1:0]                 tx_reset_done;
  logic [NIC_PORTS-1:0]                 rx_reset_done;
  logic [NIC_PORTS-1:0]                 rx_cdr_stable;

  logic [NIC_PORTS-1:0][GT_DATA_W-1:0]  gt_tx_data;
  logic [NIC_PORTS-1:0][GT_DATA_W-1:0]  gt_rx_data;
  logic [NIC_PORTS-1:0]                 rx_locked;
  logic [NIC_PORTS-1:0]                 rx_bitslip;
  logic [NIC_PORTS-1:0]                 rx_watchdog_rst;

  logic [NIC_PORTS-1:0][DROP_W-1:0]     overflow_drops;
  logic [NIC_PORTS-1:0][DROP_W-1:0]     crc_drops;
  logic [NIC_PORTS-1:0][DROP_W-1:0]     pcs_drops;

  logic [NIC_PORTS-1:0]                 rx_eth_rst;
  logic [NIC_PORTS-1:0]                 rx_axi_rst;
  logic [NIC_PORTS-1:0]                 tx_eth_rst;
  logic [NIC_PORTS-1:0]                 tx_axi_rst;

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
  assign pcie_link_up        = 1'b0;
  assign pci_express_x8_txn  = '0;
  assign pci_express_x8_txp  = '0;
  assign nic_axil.awaddr     = '0;
  assign nic_axil.awprot     = '0;
  assign nic_axil.awvalid    = 1'b0;
  assign nic_axil.wdata      = '0;
  assign nic_axil.wstrb      = '0;
  assign nic_axil.wvalid     = 1'b0;
  assign nic_axil.bready     = 1'b1;
  assign nic_axil.araddr     = '0;
  assign nic_axil.arprot     = '0;
  assign nic_axil.arvalid    = 1'b0;
  assign nic_axil.rready     = 1'b1;

  for (genvar p = 0; p < NIC_PORTS; p++) begin : g_no_pcie
    assign tx_axi_stream[p].data  = '0;
    assign tx_axi_stream[p].mask  = '0;
    assign tx_axi_stream[p].valid = 1'b0;
    assign tx_axi_stream[p].last  = 1'b0;
    assign rx_axi_stream[p].ready = 1'b1;
  end
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
      .user_lnk_up          (pcie_link_up),
      .M_AXIS_H2C_0_0_tdata (tx_axi_stream[0].data),
      .M_AXIS_H2C_0_0_tkeep (tx_axi_stream[0].mask),
      .M_AXIS_H2C_0_0_tvalid(tx_axi_stream[0].valid),
      .M_AXIS_H2C_0_0_tlast (tx_axi_stream[0].last),
      .M_AXIS_H2C_0_0_tready(tx_axi_stream[0].ready),
      .S_AXIS_C2H_0_0_tdata (rx_axi_stream[0].data),
      .S_AXIS_C2H_0_0_tkeep (rx_axi_stream[0].mask),
      .S_AXIS_C2H_0_0_tvalid(rx_axi_stream[0].valid),
      .S_AXIS_C2H_0_0_tlast (rx_axi_stream[0].last),
      .S_AXIS_C2H_0_0_tready(rx_axi_stream[0].ready),
      .M_AXIS_H2C_1_0_tdata (tx_axi_stream[1].data),
      .M_AXIS_H2C_1_0_tkeep (tx_axi_stream[1].mask),
      .M_AXIS_H2C_1_0_tvalid(tx_axi_stream[1].valid),
      .M_AXIS_H2C_1_0_tlast (tx_axi_stream[1].last),
      .M_AXIS_H2C_1_0_tready(tx_axi_stream[1].ready),
      .S_AXIS_C2H_1_0_tdata (rx_axi_stream[1].data),
      .S_AXIS_C2H_1_0_tkeep (rx_axi_stream[1].mask),
      .S_AXIS_C2H_1_0_tvalid(rx_axi_stream[1].valid),
      .S_AXIS_C2H_1_0_tlast (rx_axi_stream[1].last),
      .S_AXIS_C2H_1_0_tready(rx_axi_stream[1].ready),
      .M_AXI_LITE_0_awaddr  (nic_axil.awaddr),
      .M_AXI_LITE_0_awprot  (nic_axil.awprot),
      .M_AXI_LITE_0_awvalid (nic_axil.awvalid),
      .M_AXI_LITE_0_awready (nic_axil.awready),
      .M_AXI_LITE_0_wdata   (nic_axil.wdata),
      .M_AXI_LITE_0_wstrb   (nic_axil.wstrb),
      .M_AXI_LITE_0_wvalid  (nic_axil.wvalid),
      .M_AXI_LITE_0_wready  (nic_axil.wready),
      .M_AXI_LITE_0_bresp   (nic_axil.bresp),
      .M_AXI_LITE_0_bvalid  (nic_axil.bvalid),
      .M_AXI_LITE_0_bready  (nic_axil.bready),
      .M_AXI_LITE_0_araddr  (nic_axil.araddr),
      .M_AXI_LITE_0_arprot  (nic_axil.arprot),
      .M_AXI_LITE_0_arvalid (nic_axil.arvalid),
      .M_AXI_LITE_0_arready (nic_axil.arready),
      .M_AXI_LITE_0_rdata   (nic_axil.rdata),
      .M_AXI_LITE_0_rresp   (nic_axil.rresp),
      .M_AXI_LITE_0_rvalid  (nic_axil.rvalid),
      .M_AXI_LITE_0_rready  (nic_axil.rready)
  );
`endif

  gtwizard_ultrascale_0 gt0_inst (
      .gtwiz_reset_clk_freerun_in        (freerun_clk),
      .gtwiz_reset_all_in                (freerun_rst_q),
      .gtwiz_reset_tx_pll_and_datapath_in(1'b0),
      .gtwiz_reset_tx_datapath_in        (1'b0),
      .gtwiz_reset_rx_pll_and_datapath_in(1'b0),
      .gtwiz_reset_rx_datapath_in        (rx_watchdog_rst[0]),
      .gtwiz_userclk_tx_reset_in         (freerun_rst_q),
      .gtwiz_userclk_rx_reset_in         (freerun_rst_q),
      .gtwiz_userclk_tx_srcclk_out       (),
      .gtwiz_userclk_tx_usrclk_out       (),
      .gtwiz_userclk_tx_usrclk2_out      (tx_usrclk[0]),
      .gtwiz_userclk_tx_active_out       (tx_userclk_active[0]),
      .gtwiz_userclk_rx_srcclk_out       (),
      .gtwiz_userclk_rx_usrclk_out       (),
      .gtwiz_userclk_rx_usrclk2_out      (rx_usrclk[0]),
      .gtwiz_userclk_rx_active_out       (rx_userclk_active[0]),
      .gtrefclk00_in                     (mgtrefclk_227),
      .gtyrxp_in                         (sfp_1_rxp),
      .gtyrxn_in                         (sfp_1_rxn),
      .gtytxp_out                        (sfp_1_txp),
      .gtytxn_out                        (sfp_1_txn),
      .gtwiz_userdata_tx_in              (gt_tx_data[0]),
      .gtwiz_userdata_rx_out             (gt_rx_data[0]),
      .loopback_in                       (3'b000),
      .rxslide_in                        (rx_bitslip[0]),
      .gtpowergood_out                   (gt_powergood[0]),
      .gtwiz_reset_tx_done_out           (tx_reset_done[0]),
      .gtwiz_reset_rx_done_out           (rx_reset_done[0]),
      .gtwiz_reset_rx_cdr_stable_out     (rx_cdr_stable[0]),
      .rxpmaresetdone_out                (),
      .txpmaresetdone_out                (),
      .qpll0lock_out                     (qpll0_lock),
      .qpll0outclk_out                   (qpll0_clk),
      .qpll0outrefclk_out                (qpll0_refclk)
  );

  gtwizard_ultrascale_1 gt1_inst (
      .gtwiz_reset_clk_freerun_in        (freerun_clk),
      .gtwiz_reset_all_in                (freerun_rst_q),
      .gtwiz_reset_tx_pll_and_datapath_in(1'b0),
      .gtwiz_reset_tx_datapath_in        (1'b0),
      .gtwiz_reset_rx_pll_and_datapath_in(1'b0),
      .gtwiz_reset_rx_datapath_in        (rx_watchdog_rst[1]),
      .gtwiz_userclk_tx_reset_in         (freerun_rst_q),
      .gtwiz_userclk_rx_reset_in         (freerun_rst_q),
      .gtwiz_userclk_tx_srcclk_out       (),
      .gtwiz_userclk_tx_usrclk_out       (),
      .gtwiz_userclk_tx_usrclk2_out      (tx_usrclk[1]),
      .gtwiz_userclk_tx_active_out       (tx_userclk_active[1]),
      .gtwiz_userclk_rx_srcclk_out       (),
      .gtwiz_userclk_rx_usrclk_out       (),
      .gtwiz_userclk_rx_usrclk2_out      (rx_usrclk[1]),
      .gtwiz_userclk_rx_active_out       (rx_userclk_active[1]),
      .gtwiz_reset_qpll0lock_in          (qpll0_lock),
      .gtwiz_reset_qpll0reset_out        (),
      .qpll0clk_in                       (qpll0_clk),
      .qpll0refclk_in                    (qpll0_refclk),
      .qpll1clk_in                       (1'b0),
      .qpll1refclk_in                    (1'b0),
      .gtyrxp_in                         (sfp_2_rxp),
      .gtyrxn_in                         (sfp_2_rxn),
      .gtytxp_out                        (sfp_2_txp),
      .gtytxn_out                        (sfp_2_txn),
      .gtwiz_userdata_tx_in              (gt_tx_data[1]),
      .gtwiz_userdata_rx_out             (gt_rx_data[1]),
      .loopback_in                       (3'b000),
      .rxslide_in                        (rx_bitslip[1]),
      .gtpowergood_out                   (gt_powergood[1]),
      .gtwiz_reset_tx_done_out           (tx_reset_done[1]),
      .gtwiz_reset_rx_done_out           (rx_reset_done[1]),
      .gtwiz_reset_rx_cdr_stable_out     (rx_cdr_stable[1]),
      .rxpmaresetdone_out                (),
      .txpmaresetdone_out                ()
  );

  assign axi_rst = !axi_aresetn;

  nic_regs nic_regs_inst (
      .axi_clk       (axi_aclk),
      .axi_rst       (axi_rst),
      .s_axil        (nic_axil),
      .eth_clk       (rx_usrclk),
      .eth_rst       (cfg_eth_rst),
      .rss_key_o     (rss_key),
      .udp_ports_en_o(udp_ports_en),
      .reta_o        (reta)
  );

  for (genvar p = 0; p < NIC_PORTS; p++) begin : g_port
    logic       rx_ready;
    logic       tx_ready;
    logic       rx_link_rst;
    logic       tx_link_rst;
    logic [1:0] link_rst_sync [2];
    logic       rx_link_rst_sync;
    logic       tx_link_rst_sync;

    always_comb begin
      rx_ready    = rx_reset_done[p] && rx_userclk_active[p] && gt_powergood[p];
      tx_ready    = tx_reset_done[p] && tx_userclk_active[p] && gt_powergood[p];
      rx_link_rst = !rx_ready || axi_rst;
      tx_link_rst = !tx_ready || axi_rst;
    end

    shift_reg #(
        .DATA_W    (2),
        .PIPE_DEPTH(2),
        .RST_EN    (1),
        .RST_VAL   ('1)
    ) link_rst_sync_inst (
        .clk   (freerun_clk),
        .rst   (freerun_rst_q),
        .data_i({rx_link_rst, tx_link_rst}),
        .data_o(link_rst_sync)
    );

    assign {rx_link_rst_sync, tx_link_rst_sync} = link_rst_sync[1];

    rst_sync rx_eth_rst_sync_inst (
        .clk  (rx_usrclk[p]),
        .rst_i(rx_link_rst_sync),
        .rst_o(rx_eth_rst[p])
    );

    rst_sync rx_axi_rst_sync_inst (
        .clk  (axi_aclk),
        .rst_i(rx_link_rst_sync),
        .rst_o(rx_axi_rst[p])
    );

    rst_sync tx_eth_rst_sync_inst (
        .clk  (tx_usrclk[p]),
        .rst_i(tx_link_rst_sync),
        .rst_o(tx_eth_rst[p])
    );

    rst_sync tx_axi_rst_sync_inst (
        .clk  (axi_aclk),
        .rst_i(tx_link_rst_sync),
        .rst_o(tx_axi_rst[p])
    );

    rst_sync cfg_eth_rst_sync_inst (
        .clk  (rx_usrclk[p]),
        .rst_i(axi_rst),
        .rst_o(cfg_eth_rst[p])
    );

    rx_lock_watchdog rx_lock_watchdog_inst (
        .clk            (freerun_clk),
        .rst            (freerun_rst_q),
        .rx_reset_done_i(rx_reset_done[p]),
        .locked_i       (rx_locked[p]),
        .rx_reset_o     (rx_watchdog_rst[p])
    );

    rx_top #(
        .DIN_W       (GT_DATA_W),
        .GOOD_COUNT  (64),
        .BAD_COUNT   (8),
        .BITSLIP_WAIT(256),
        .FIFO_DEPTH  (2048),
        .DROP_COUNT_W(DROP_W)
    ) rx_top_inst (
        .eth_clk         (rx_usrclk[p]),
        .eth_rst         (rx_eth_rst[p]),
        .axi_clk         (axi_aclk),
        .axi_rst         (rx_axi_rst[p]),
        .raw_data_i      (gt_rx_data[p]),
        .raw_valid_i     (1'b1),
        .rss_key_i       (rss_key[p]),
        .udp_ports_en_i  (udp_ports_en[p]),
        .reta_i          (reta[p]),
        .locked_o        (rx_locked[p]),
        .bitslip_o       (rx_bitslip[p]),
        .overflow_drops_o(overflow_drops[p]),
        .crc_drops_o     (crc_drops[p]),
        .pcs_drops_o     (pcs_drops[p]),
        .pcs_stream_o    (),
        .crc_drop_o      (),
        .fifo_cancel_o   (),
        .m_axi           (rx_axi_stream[p])
    );

    tx_top #(
        .FIFO_DEPTH      (128),
        .SCRAMBLER_BYPASS(SCRAMBLER_BYPASS)
    ) tx_top_inst (
        .axi_clk    (axi_aclk),
        .axi_rst    (tx_axi_rst[p]),
        .eth_clk    (tx_usrclk[p]),
        .eth_rst    (tx_eth_rst[p]),
        .s_axi      (tx_axi_stream[p]),
        .raw_data_o (gt_tx_data[p]),
        .raw_valid_o()
    );
  end

  assign led_g     = pcie_link_up;
  assign sfp_1_led = rx_locked[0];
  assign sfp_2_led = rx_locked[1];

endmodule
