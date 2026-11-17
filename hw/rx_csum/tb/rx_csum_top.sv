module rx_csum_top
  import pcs_pkg::*;
  import parser_pkg::*;
(
  input  logic                    clk,
  input  logic                    rst,

  input  logic [ETH_DATA_W-1:0]   data_i,
  input  logic [LAST_BYTES_W-1:0] last_bytes_i,
  input  logic                    valid_i,
  input  logic                    last_i,
  input  logic                    drop_i,

  output logic [ETH_DATA_W-1:0]   out_data_o,
  output logic [LAST_BYTES_W-1:0] out_last_bytes_o,
  output logic                    out_valid_o,
  output logic                    out_last_o,
  output logic                    out_drop_o,
  output logic                    csum_valid_o,
  output logic [CSUM_W-1:0]       csum_o
);

  rx_eth_stream_t eth_stream_in;

  always_comb begin
    eth_stream_in.data       = data_i;
    eth_stream_in.last_bytes = last_bytes_i;
    eth_stream_in.valid      = valid_i;
    eth_stream_in.last       = last_i;
    eth_stream_in.drop       = drop_i;
  end

  rx_csum rx_csum_inst (
      .clk         (clk),
      .rst         (rst),
      .eth_stream_i(eth_stream_in),
      .csum_valid_o(csum_valid_o),
      .csum_o      (csum_o)
  );

  data_status_pipeline #(
      .DATA_W    (ETH_DATA_W + LAST_BYTES_W + 1),
      .STATUS_W  (2),
      .PIPE_DEPTH(RX_CSUM_LATENCY)
  ) stream_pipeline_inst (
      .clk     (clk),
      .rst     (rst),
      .data_i  ({data_i, last_bytes_i, last_i}),
      .status_i({valid_i, drop_i}),
      .data_o  ({out_data_o, out_last_bytes_o, out_last_o}),
      .status_o({out_valid_o, out_drop_o})
  );

endmodule
