module eth_stage_top
  import parser_pkg::*;
#(
  parameter int DATA_W = 256
) (
  input  logic                    axi_clk,
  input  logic                    axi_rst,

  output logic [OFF_W-1:0]        meta_pos,
  output logic                    meta_eth_ok,
  output logic [ETHERTYPE_W-1:0]  meta_ethertype,
  output logic [VLAN_COUNT_W-1:0] meta_vlan_count,
  output logic [OFF_W-1:0]        meta_payload_off
);

  axi_stream_if #(.DATA_W(DATA_W)) s_axi ();
  axi_stream_if #(.DATA_W(DATA_W)) m_axi ();

  parse_meta_t meta;

  eth_stage eth_stage_inst (
      .clk   (axi_clk),
      .rst   (axi_rst),
      .s_axi (s_axi),
      .m_axi (m_axi),
      .meta_o(meta)
  );

  always_comb begin
    meta_pos         = meta.pos;
    meta_eth_ok      = meta.eth_ok;
    meta_ethertype   = meta.ethertype;
    meta_vlan_count  = meta.vlan_count;
    meta_payload_off = meta.payload_off;
  end

endmodule
