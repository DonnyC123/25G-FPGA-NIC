module pkt_parser
  import parser_pkg::*;
#(
  parameter int EXT_STAGES = 2
) (
  input  logic                clk,
  input  logic                rst,
         axi_stream_if.slave  s_axi,
         axi_stream_if.master m_axi,
  output parse_meta_t         meta_o
);

  localparam int DATA_W = s_axi.DATA_W;

  axi_stream_if #(.DATA_W(DATA_W)) eth_axi ();
  axi_stream_if #(.DATA_W(DATA_W)) ipv4_axi ();
  axi_stream_if #(.DATA_W(DATA_W)) ext_axi[EXT_STAGES+1] ();
  axi_stream_if #(.DATA_W(DATA_W)) tcp_axi ();

  parse_meta_t                  eth_meta;
  parse_meta_t                  ipv4_meta;
  parse_meta_t [EXT_STAGES:0]   ext_meta;
  parse_meta_t                  tcp_meta;

  eth_stage eth_stage_inst (
      .clk   (clk),
      .rst   (rst),
      .s_axi (s_axi),
      .m_axi (eth_axi),
      .meta_o(eth_meta)
  );

  ipv4_stage ipv4_stage_inst (
      .clk   (clk),
      .rst   (rst),
      .s_axi (eth_axi),
      .meta_i(eth_meta),
      .m_axi (ipv4_axi),
      .meta_o(ipv4_meta)
  );

  ipv6_stage ipv6_stage_inst (
      .clk   (clk),
      .rst   (rst),
      .s_axi (ipv4_axi),
      .meta_i(ipv4_meta),
      .m_axi (ext_axi[0]),
      .meta_o(ext_meta[0])
  );

  for (genvar i = 0; i < EXT_STAGES; i++) begin : g_ext
    ipv6_ext_stage ipv6_ext_stage_inst (
        .clk   (clk),
        .rst   (rst),
        .s_axi (ext_axi[i]),
        .meta_i(ext_meta[i]),
        .m_axi (ext_axi[i+1]),
        .meta_o(ext_meta[i+1])
    );
  end

  tcp_stage tcp_stage_inst (
      .clk   (clk),
      .rst   (rst),
      .s_axi (ext_axi[EXT_STAGES]),
      .meta_i(ext_meta[EXT_STAGES]),
      .m_axi (tcp_axi),
      .meta_o(tcp_meta)
  );

  udp_stage udp_stage_inst (
      .clk   (clk),
      .rst   (rst),
      .s_axi (tcp_axi),
      .meta_i(tcp_meta),
      .m_axi (m_axi),
      .meta_o(meta_o)
  );

endmodule
