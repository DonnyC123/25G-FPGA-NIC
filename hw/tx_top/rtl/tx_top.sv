module tx_top
  import pcs_pkg::*;
#(
  parameter int FIFO_DEPTH       = 64,
  parameter int MIN_FRAME_BYTES  = 60,
  parameter int SCRAMBLER_BYPASS = 0
) (
  input  logic                     axi_clk,
  input  logic                     axi_rst,
  input  logic                     eth_clk,
  input  logic                     eth_rst,

         axi_stream_if.slave       s_axi,

  output logic [PCS_PAYLOAD_W-1:0] raw_data_o,
  output logic                     raw_valid_o
);

  tx_eth_stream_if #(.DATA_W(PCS_PAYLOAD_W)) fifo_stream ();

  tx_fifo_ctrl #(
      .FIFO_DEPTH(FIFO_DEPTH)
  ) tx_fifo_ctrl_inst (
      .s_clk      (axi_clk),
      .s_rst      (axi_rst),
      .m_clk      (eth_clk),
      .m_rst      (eth_rst),
      .s_axi      (s_axi),
      .tx_stream_o(fifo_stream)
  );

  tx_pcs #(
      .MIN_FRAME_BYTES (MIN_FRAME_BYTES),
      .SCRAMBLER_BYPASS(SCRAMBLER_BYPASS)
  ) tx_pcs_inst (
      .clk        (eth_clk),
      .rst        (eth_rst),
      .tx_stream_i(fifo_stream),
      .raw_data_o (raw_data_o),
      .raw_valid_o(raw_valid_o)
  );

endmodule
