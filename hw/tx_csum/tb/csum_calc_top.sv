module csum_calc_top
  import parser_pkg::*;
#(
  parameter int DATA_W     = 256,
  parameter int OPT_STAGES = 4,
  parameter int EXT_STAGES = 2
) (
  input  logic                             axi_clk,
  input  logic                             axi_rst,

  output logic [$bits(csum_result_t)-1:0]  result_o,
  output logic                             result_valid_o
);

  axi_stream_if #(.DATA_W(DATA_W)) s_axi ();
  axi_stream_if #(.DATA_W(DATA_W)) m_axi ();

  parse_meta_t  meta;
  csum_result_t result;

  pkt_parser #(
      .OPT_STAGES(OPT_STAGES),
      .EXT_STAGES(EXT_STAGES)
  ) pkt_parser_inst (
      .clk   (axi_clk),
      .rst   (axi_rst),
      .s_axi (s_axi),
      .m_axi (m_axi),
      .meta_o(meta)
  );

  csum_calc #(
      .DATA_W(DATA_W)
  ) csum_calc_inst (
      .clk           (axi_clk),
      .rst           (axi_rst),
      .data_i        (m_axi.data),
      .mask_i        (m_axi.mask),
      .last_i        (m_axi.last),
      .accept_i      (m_axi.valid && m_axi.ready),
      .meta_i        (meta),
      .result_o      (result),
      .result_valid_o(result_valid_o)
  );

  assign result_o = result;

endmodule
