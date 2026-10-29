module tx_fifo_top #(
  parameter int S_DATA_W   = 256,
  parameter int M_DATA_W   = 64,
  parameter int FIFO_DEPTH = 64
) (
  input  logic axi_clk,
  input  logic axi_rst,
  input  logic eth_clk,
  input  logic eth_rst
);

  axi_stream_if #(.DATA_W(S_DATA_W)) s_axi ();

  tx_eth_stream_if #(.DATA_W(M_DATA_W)) tx_stream ();

  tx_fifo_ctrl #(
      .FIFO_DEPTH(FIFO_DEPTH)
  ) tx_fifo_ctrl_inst (
      .s_clk      (axi_clk),
      .s_rst      (axi_rst),
      .m_clk      (eth_clk),
      .m_rst      (eth_rst),
      .s_axi      (s_axi),
      .tx_stream_o(tx_stream)
  );

endmodule
