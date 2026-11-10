module pkt_parser_top
  import parser_pkg::*;
#(
  parameter int DATA_W     = 256,
  parameter int EXT_STAGES = 2
) (
  input  logic                             axi_clk,
  input  logic                             axi_rst,

  output logic [$bits(parse_meta_t)-1:0]   meta_o
);

  axi_stream_if #(.DATA_W(DATA_W)) s_axi ();
  axi_stream_if #(.DATA_W(DATA_W)) m_axi ();

  parse_meta_t meta;

  pkt_parser #(
      .EXT_STAGES(EXT_STAGES)
  ) pkt_parser_inst (
      .clk   (axi_clk),
      .rst   (axi_rst),
      .s_axi (s_axi),
      .m_axi (m_axi),
      .meta_o(meta)
  );

  assign meta_o = meta;

endmodule
