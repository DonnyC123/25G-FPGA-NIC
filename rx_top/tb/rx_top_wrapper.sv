module rx_top_wrapper #(
  parameter int DIN_W        = 64,
  parameter int M_AXI_W      = 256,
  parameter int GOOD_COUNT   = 1,
  parameter int BAD_COUNT    = 8,
  parameter int BITSLIP_WAIT = 3,
  parameter int FIFO_DEPTH   = 64,
  parameter int DROP_COUNT_W = 32
) (
  input  logic                    eth_clk,
  input  logic                    eth_rst,
  input  logic                    axi_clk,
  input  logic                    axi_rst,
  input  logic [DIN_W-1:0]        raw_data_i,
  input  logic                    raw_valid_i,

  output logic                    locked_o,
  output logic                    bitslip_o,

  output logic [DROP_COUNT_W-1:0] overflow_drops_o,
  output logic [DROP_COUNT_W-1:0] crc_drops_o,
  output logic [DROP_COUNT_W-1:0] pcs_drops_o
);

  axi_stream_if #(.DATA_W(M_AXI_W)) m_axi ();

  rx_top #(
      .DIN_W       (DIN_W),
      .GOOD_COUNT  (GOOD_COUNT),
      .BAD_COUNT   (BAD_COUNT),
      .BITSLIP_WAIT(BITSLIP_WAIT),
      .FIFO_DEPTH  (FIFO_DEPTH),
      .DROP_COUNT_W(DROP_COUNT_W)
  ) rx_top_inst (
      .eth_clk         (eth_clk),
      .eth_rst         (eth_rst),
      .axi_clk         (axi_clk),
      .axi_rst         (axi_rst),
      .raw_data_i      (raw_data_i),
      .raw_valid_i     (raw_valid_i),
      .locked_o        (locked_o),
      .bitslip_o       (bitslip_o),
      .overflow_drops_o(overflow_drops_o),
      .crc_drops_o     (crc_drops_o),
      .pcs_drops_o     (pcs_drops_o),
      .m_axi           (m_axi)
  );

endmodule
