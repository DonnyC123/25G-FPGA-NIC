module nic_regs
  import rss_pkg::*;
  import nic_regs_pkg::*;
(
  input  logic                                                              axi_clk,
  input  logic                                                              axi_rst,
         axi4_lite_if.slave                                                 s_axil,

  input  logic              [NIC_PORTS-1:0]                                 eth_clk,
  input  logic              [NIC_PORTS-1:0]                                 eth_rst,
  output logic              [NIC_PORTS-1:0][RSS_KEY_W-1:0]                  rss_key_o,
  output logic              [NIC_PORTS-1:0]                                 udp_ports_en_o,
  output logic              [NIC_PORTS-1:0][RETA_SIZE-1:0][RSS_QUEUE_W-1:0] reta_o
);

  localparam int                        SLOT_W      = $clog2(RSS_REGS_WORDS);

  localparam logic [NIC_REGS_IDX_W-1:0] VERSION_IDX = NIC_REGS_IDX_W'(REG_VERSION_OFF / NIC_REGS_WORD_BYTES);
  localparam logic [NIC_REGS_IDX_W-1:0] RSS_IDX     = NIC_REGS_IDX_W'(REG_RSS_CTRL_OFF / NIC_REGS_WORD_BYTES);

  localparam logic [1:0]                RESP_OKAY   = 2'b00;

  if (s_axil.DATA_W != NIC_REGS_DATA_W) begin : g_data_width_check
    $error("s_axil.DATA_W (%0d) must be %0d", s_axil.DATA_W, NIC_REGS_DATA_W);
  end

  localparam rss_regs_t RESET_REGS = '{reta: '0, key: {<<NIC_REGS_DATA_W{RSS_DEFAULT_KEY}}, ctrl: '0};

  logic      [NIC_REGS_PORT_SEL_W-1:0] wr_sel;
  logic      [NIC_REGS_PORT_SEL_W-1:0] rd_sel;
  logic      [NIC_PORT_W-1:0]          wr_port;
  logic      [NIC_PORT_W-1:0]          rd_port;
  logic                                wr_port_ok;
  logic                                rd_port_ok;
  logic      [NIC_REGS_IDX_W-1:0]      wr_idx;
  logic      [NIC_REGS_IDX_W-1:0]      rd_idx;
  logic      [NIC_REGS_IDX_W-1:0]      wr_slot;
  logic      [NIC_REGS_IDX_W-1:0]      rd_slot;
  logic                                wr_rss;
  logic                                rd_rss;
  logic                                wr_fire;
  logic                                rd_fire;
  logic      [NIC_REGS_DATA_W-1:0]     wr_data;
  logic      [NIC_REGS_DATA_W-1:0]     rd_data;

  rss_cfg_t  [NIC_PORTS-1:0]           cfg_d;
  rss_cfg_t  [NIC_PORTS-1:0]           cfg_q;
  logic      [NIC_PORTS-1:0]           dirty_d;
  logic      [NIC_PORTS-1:0]           dirty_q;
  logic      [NIC_PORTS-1:0]           handshake_ready;
  logic      [NIC_PORTS-1:0]           send;

  logic                                bvalid_d;
  logic                                bvalid_q;
  logic                                rvalid_d;
  logic                                rvalid_q;
  logic      [NIC_REGS_DATA_W-1:0]     rdata_d;
  logic      [NIC_REGS_DATA_W-1:0]     rdata_q;

  always_comb begin
    wr_sel     = s_axil.awaddr[NIC_REGS_ADDR_W-1:NIC_REGS_PORT_ADDR_W];
    rd_sel     = s_axil.araddr[NIC_REGS_ADDR_W-1:NIC_REGS_PORT_ADDR_W];
    wr_port    = wr_sel[NIC_PORT_W-1:0];
    rd_port    = rd_sel[NIC_PORT_W-1:0];
    wr_port_ok = wr_sel < NIC_REGS_PORT_SEL_W'(NIC_PORTS);
    rd_port_ok = rd_sel < NIC_REGS_PORT_SEL_W'(NIC_PORTS);
    wr_idx     = s_axil.awaddr[NIC_REGS_PORT_ADDR_W-1:2];
    rd_idx     = s_axil.araddr[NIC_REGS_PORT_ADDR_W-1:2];
    wr_slot    = wr_idx - RSS_IDX;
    rd_slot    = rd_idx - RSS_IDX;
    wr_rss     = wr_port_ok && wr_slot < NIC_REGS_IDX_W'(RSS_REGS_WORDS);
    rd_rss     = rd_port_ok && rd_slot < NIC_REGS_IDX_W'(RSS_REGS_WORDS);
    wr_fire    = s_axil.awvalid && s_axil.wvalid && !bvalid_q;
    rd_fire    = s_axil.arvalid && !rvalid_q;
    send       = dirty_q & handshake_ready;

    wr_data = cfg_q[wr_port].words[wr_slot[SLOT_W-1:0]];
    for (int b = 0; b < NIC_REGS_WORD_BYTES; b++) begin
      if (s_axil.wstrb[b]) begin
        wr_data[b*8+:8] = s_axil.wdata[b*8+:8];
      end
    end

    rd_data = '0;
    if (rd_port_ok && rd_idx == VERSION_IDX) begin
      rd_data = NIC_REGS_VERSION;
    end
    if (rd_rss) begin
      rd_data = cfg_q[rd_port].words[rd_slot[SLOT_W-1:0]];
    end
  end

  always_comb begin
    cfg_d   = cfg_q;
    dirty_d = dirty_q & ~send;

    if (wr_fire && wr_rss) begin
      cfg_d[wr_port].words[wr_slot[SLOT_W-1:0]] = wr_data;
      dirty_d[wr_port]                          = 1'b1;
    end
  end

  always_comb begin
    bvalid_d = bvalid_q;
    rvalid_d = rvalid_q;
    rdata_d  = rdata_q;

    if (s_axil.bvalid && s_axil.bready) begin
      bvalid_d = 1'b0;
    end
    if (wr_fire) begin
      bvalid_d = 1'b1;
    end

    if (s_axil.rvalid && s_axil.rready) begin
      rvalid_d = 1'b0;
    end
    if (rd_fire) begin
      rvalid_d = 1'b1;
      rdata_d  = rd_data;
    end
  end

  always_ff @(posedge axi_clk) begin
    if (axi_rst) begin
      for (int p = 0; p < NIC_PORTS; p++) begin
        cfg_q[p].regs <= RESET_REGS;
      end
      dirty_q  <= '1;
      bvalid_q <= 1'b0;
      rvalid_q <= 1'b0;
    end else begin
      cfg_q    <= cfg_d;
      dirty_q  <= dirty_d;
      bvalid_q <= bvalid_d;
      rvalid_q <= rvalid_d;
    end
  end

  always_ff @(posedge axi_clk) begin
    rdata_q <= rdata_d;
  end

  for (genvar p = 0; p < NIC_PORTS; p++) begin : g_port
    rss_regs_t apply_regs;
    logic      apply;
    rss_regs_t eth_regs_d;
    rss_regs_t eth_regs_q;

    handshake_cdc #(
        .DATA_W($bits(rss_regs_t))
    ) handshake_cdc_inst (
        .src_clk    (axi_clk),
        .src_rst    (axi_rst),
        .src_data_i (cfg_q[p].regs),
        .src_valid_i(dirty_q[p]),
        .src_ready_o(handshake_ready[p]),
        .dst_clk    (eth_clk[p]),
        .dst_rst    (eth_rst[p]),
        .dst_data_o (apply_regs),
        .dst_valid_o(apply)
    );

    always_comb begin
      eth_regs_d = eth_regs_q;
      if (apply) begin
        eth_regs_d = apply_regs;
      end
    end

    always_ff @(posedge eth_clk[p]) begin
      eth_regs_q <= eth_regs_d;
    end

    always_comb begin
      rss_key_o[p]      = {<<NIC_REGS_DATA_W{eth_regs_q.key}};
      reta_o[p]         = eth_regs_q.reta;
      udp_ports_en_o[p] = eth_regs_q.ctrl[RSS_CTRL_UDP_PORTS_BIT];
    end
  end

  always_comb begin
    s_axil.awready = wr_fire;
    s_axil.wready  = wr_fire;
    s_axil.bresp   = RESP_OKAY;
    s_axil.bvalid  = bvalid_q;
    s_axil.arready = rd_fire;
    s_axil.rdata   = rdata_q;
    s_axil.rresp   = RESP_OKAY;
    s_axil.rvalid  = rvalid_q;
  end
endmodule
