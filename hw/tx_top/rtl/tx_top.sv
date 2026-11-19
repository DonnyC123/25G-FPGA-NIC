module tx_top
  import pcs_pkg::*;
  import tx_meta_pkg::csum_result_t;
  import tx_meta_pkg::tx_meta_t;
  import tx_meta_pkg::TX_META_BYTES;
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

  localparam int CSUM_FIFO_DEPTH = 2 * FIFO_DEPTH;

  axi_stream_if #(.DATA_W(s_axi.DATA_W)) frame_axi ();

  tx_eth_stream_if #(.DATA_W(PCS_PAYLOAD_W)) fifo_stream ();
  tx_eth_stream_if #(.DATA_W(PCS_PAYLOAD_W)) csum_stream ();

  tx_meta_t                 frame_meta;
  logic [TX_META_BYTES-1:0] frame_csum_mask;

  csum_result_t             csum_result;
  logic                     csum_result_valid;
  csum_result_t             fifo_result;
  logic                     fifo_result_valid;
  logic                     fifo_result_ready;
  csum_result_t             skid_result;
  logic                     skid_result_valid;
  logic                     skid_result_ready;

  tx_meta tx_meta_inst (
      .clk   (axi_clk),
      .rst   (axi_rst),
      .s_axi (s_axi),
      .m_axi (frame_axi),
      .meta_o     (frame_meta),
      .csum_mask_o(frame_csum_mask)
  );

  csum_sum csum_sum_inst (
      .clk           (axi_clk),
      .rst           (axi_rst),
      .s_axi         (frame_axi),
      .csum_mask_i   (frame_csum_mask),
      .meta_i        (frame_meta),
      .result_o      (csum_result),
      .result_valid_o(csum_result_valid)
  );

  async_fifo #(
      .DATA_W    ($bits(csum_result_t)),
      .FIFO_DEPTH(CSUM_FIFO_DEPTH)
  ) csum_fifo_inst (
      .wr_clk (axi_clk),
      .wr_rst (axi_rst),
      .rd_clk (eth_clk),
      .rd_rst (eth_rst),
      .data_i (csum_result),
      .valid_i(csum_result_valid),
      .ready_o(),
      .data_o (fifo_result),
      .valid_o(fifo_result_valid),
      .ready_i(fifo_result_ready)
  );

  skid_buffer #(
      .DATA_W($bits(csum_result_t))
  ) csum_skid_inst (
      .clk    (eth_clk),
      .rst    (eth_rst),
      .data_i (fifo_result),
      .valid_i(fifo_result_valid),
      .ready_o(fifo_result_ready),
      .data_o (skid_result),
      .valid_o(skid_result_valid),
      .ready_i(skid_result_ready)
  );

  tx_fifo_ctrl #(
      .FIFO_DEPTH(FIFO_DEPTH)
  ) tx_fifo_ctrl_inst (
      .s_clk      (axi_clk),
      .s_rst      (axi_rst),
      .m_clk      (eth_clk),
      .m_rst      (eth_rst),
      .s_axi      (frame_axi),
      .tx_stream_o(fifo_stream)
  );

  csum_insert csum_insert_inst (
      .clk           (eth_clk),
      .rst           (eth_rst),
      .s_stream      (fifo_stream),
      .result_i      (skid_result),
      .result_valid_i(skid_result_valid),
      .result_ready_o(skid_result_ready),
      .m_stream      (csum_stream)
  );

  tx_pcs #(
      .MIN_FRAME_BYTES (MIN_FRAME_BYTES),
      .SCRAMBLER_BYPASS(SCRAMBLER_BYPASS)
  ) tx_pcs_inst (
      .clk        (eth_clk),
      .rst        (eth_rst),
      .tx_stream_i(csum_stream),
      .raw_data_o (raw_data_o),
      .raw_valid_o(raw_valid_o)
  );

endmodule
