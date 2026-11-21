module nic_regs_top
  import rss_pkg::*;
  import nic_regs_pkg::*;
(
  input  logic                               axi_clk,
  input  logic                               axi_rst,
  input  logic                               eth_clk,
  input  logic                               eth_rst,

  input  logic [31:0]                        s_axil_awaddr,
  input  logic [2:0]                         s_axil_awprot,
  input  logic                               s_axil_awvalid,
  output logic                               s_axil_awready,
  input  logic [31:0]                        s_axil_wdata,
  input  logic [3:0]                         s_axil_wstrb,
  input  logic                               s_axil_wvalid,
  output logic                               s_axil_wready,
  output logic [1:0]                         s_axil_bresp,
  output logic                               s_axil_bvalid,
  input  logic                               s_axil_bready,
  input  logic [31:0]                        s_axil_araddr,
  input  logic [2:0]                         s_axil_arprot,
  input  logic                               s_axil_arvalid,
  output logic                               s_axil_arready,
  output logic [31:0]                        s_axil_rdata,
  output logic [1:0]                         s_axil_rresp,
  output logic                               s_axil_rvalid,
  input  logic                               s_axil_rready,

  output logic [RSS_KEY_W-1:0]               rss_key_o,
  output logic                               udp_ports_en_o,
  output logic [RETA_SIZE*RSS_QUEUE_W-1:0]   reta_o
);

  axi4_lite_if s_axil ();

  logic [NIC_PORTS-1:0][RSS_KEY_W-1:0]                  rss_key;
  logic [NIC_PORTS-1:0]                                 udp_ports_en;
  logic [NIC_PORTS-1:0][RETA_SIZE-1:0][RSS_QUEUE_W-1:0] reta;

  always_comb begin
    s_axil.awaddr  = s_axil_awaddr;
    s_axil.awprot  = s_axil_awprot;
    s_axil.awvalid = s_axil_awvalid;
    s_axil.wdata   = s_axil_wdata;
    s_axil.wstrb   = s_axil_wstrb;
    s_axil.wvalid  = s_axil_wvalid;
    s_axil.bready  = s_axil_bready;
    s_axil.araddr  = s_axil_araddr;
    s_axil.arprot  = s_axil_arprot;
    s_axil.arvalid = s_axil_arvalid;
    s_axil.rready  = s_axil_rready;
  end

  nic_regs nic_regs_inst (
      .axi_clk       (axi_clk),
      .axi_rst       (axi_rst),
      .s_axil        (s_axil),
      .eth_clk       ({NIC_PORTS{eth_clk}}),
      .eth_rst       ({NIC_PORTS{eth_rst}}),
      .rss_key_o     (rss_key),
      .udp_ports_en_o(udp_ports_en),
      .reta_o        (reta)
  );

  always_comb begin
    s_axil_awready = s_axil.awready;
    s_axil_wready  = s_axil.wready;
    s_axil_bresp   = s_axil.bresp;
    s_axil_bvalid  = s_axil.bvalid;
    s_axil_arready = s_axil.arready;
    s_axil_rdata   = s_axil.rdata;
    s_axil_rresp   = s_axil.rresp;
    s_axil_rvalid  = s_axil.rvalid;
    rss_key_o      = rss_key[0];
    udp_ports_en_o = udp_ports_en[0];
    reta_o         = reta[0];
  end

endmodule
