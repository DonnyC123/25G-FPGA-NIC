module tx_top
  import pcs_pkg::*;
  import parser_pkg::parse_meta_t;
  import parser_pkg::csum_result_t;
#(
  parameter int FIFO_DEPTH       = 64,
  parameter int MIN_FRAME_BYTES  = 60,
  parameter int SCRAMBLER_BYPASS = 0,
  parameter int EXT_STAGES       = 2
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

  axi_stream_if #(.DATA_W(s_axi.DATA_W)) parsed_axi ();

  tx_eth_stream_if #(.DATA_W(PCS_PAYLOAD_W)) fifo_stream ();
  tx_eth_stream_if #(.DATA_W(PCS_PAYLOAD_W)) csum_stream ();

  parse_meta_t  parse_meta;

  csum_result_t csum_result;
  logic         csum_result_valid;
  csum_result_t fifo_result;
  logic         fifo_result_valid;
  logic         fifo_result_ready;

  pkt_parser #(
      .EXT_STAGES(EXT_STAGES)
  ) pkt_parser_inst (
      .clk   (axi_clk),
      .rst   (axi_rst),
      .s_axi (s_axi),
      .m_axi (parsed_axi),
      .meta_o(parse_meta)
  );

  csum_calc #(
      .DATA_W(s_axi.DATA_W)
  ) csum_calc_inst (
      .clk           (axi_clk),
      .rst           (axi_rst),
      .data_i        (parsed_axi.data),
      .mask_i        (parsed_axi.mask),
      .last_i        (parsed_axi.last),
      .accept_i      (parsed_axi.valid && parsed_axi.ready),
      .meta_i        (parse_meta),
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

  tx_fifo_ctrl #(
      .FIFO_DEPTH(FIFO_DEPTH)
  ) tx_fifo_ctrl_inst (
      .s_clk      (axi_clk),
      .s_rst      (axi_rst),
      .m_clk      (eth_clk),
      .m_rst      (eth_rst),
      .s_axi      (parsed_axi),
      .tx_stream_o(fifo_stream)
  );

  csum_insert csum_insert_inst (
      .clk           (eth_clk),
      .rst           (eth_rst),
      .s_stream      (fifo_stream),
      .result_i      (fifo_result),
      .result_valid_i(fifo_result_valid),
      .result_ready_o(fifo_result_ready),
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
