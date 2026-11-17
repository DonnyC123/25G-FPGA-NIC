module rx_parser_top
  import pcs_pkg::*;
  import parser_pkg::*;
(
  input  logic                               clk,
  input  logic                               rst,

  input  logic [ETH_DATA_W-1:0]              data_i,
  input  logic [LAST_BYTES_W-1:0]            last_bytes_i,
  input  logic                               valid_i,
  input  logic                               last_i,
  input  logic                               drop_i,

  output logic [ETH_DATA_W-1:0]              out_data_o,
  output logic [LAST_BYTES_W-1:0]            out_last_bytes_o,
  output logic                               out_valid_o,
  output logic                               out_last_o,
  output logic                               out_drop_o,
  output logic                               meta_valid_o,
  output logic [$bits(rx_parse_meta_t)-1:0] meta_o
);

  rx_eth_stream_t eth_stream_in;
  rx_eth_stream_t eth_stream_out;
  rx_parse_meta_t meta;

  always_comb begin
    eth_stream_in.data       = data_i;
    eth_stream_in.last_bytes = last_bytes_i;
    eth_stream_in.valid      = valid_i;
    eth_stream_in.last       = last_i;
    eth_stream_in.drop       = drop_i;
  end

  rx_parser rx_parser_inst (
      .clk         (clk),
      .rst         (rst),
      .eth_stream_i(eth_stream_in),
      .eth_stream_o(eth_stream_out),
      .meta_valid_o(meta_valid_o),
      .meta_o      (meta)
  );

  always_comb begin
    out_data_o       = eth_stream_out.data;
    out_last_bytes_o = eth_stream_out.last_bytes;
    out_valid_o      = eth_stream_out.valid;
    out_last_o       = eth_stream_out.last;
    out_drop_o       = eth_stream_out.drop;
    meta_o           = meta;
  end

endmodule
