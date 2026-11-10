module csum_insert_top
  import parser_pkg::*;
#(
  parameter int DATA_W = 64
) (
  input  logic                             eth_clk,
  input  logic                             eth_rst,

  input  logic [$bits(csum_result_t)-1:0]  result_i,
  input  logic                             result_valid_i,
  output logic                             result_ready_o
);

  tx_eth_stream_if #(.DATA_W(DATA_W)) tx_stream_i ();
  tx_eth_stream_if #(.DATA_W(DATA_W)) tx_stream ();

  csum_insert csum_insert_inst (
      .clk           (eth_clk),
      .rst           (eth_rst),
      .s_stream      (tx_stream_i),
      .result_i      (csum_result_t'(result_i)),
      .result_valid_i(result_valid_i),
      .result_ready_o(result_ready_o),
      .m_stream      (tx_stream)
  );

endmodule
