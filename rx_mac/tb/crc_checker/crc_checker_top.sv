module crc_checker_top
  import pcs_pkg::*;
(
  input  logic                    clk,
  input  logic                    rst,

  input  logic [ETH_DATA_W-1:0]   data_i,
  input  logic [LAST_BYTES_W-1:0] last_bytes_i,
  input  logic                    valid_i,
  input  logic                    last_i,
  input  logic                    drop_i,

  output logic                    drop_o
);

  rx_eth_stream_t eth_stream;

  always_comb begin
    eth_stream.data       = data_i;
    eth_stream.last_bytes = last_bytes_i;
    eth_stream.valid      = valid_i;
    eth_stream.last       = last_i;
    eth_stream.drop       = drop_i;
  end

  crc_checker crc_checker_inst (
      .clk         (clk),
      .rst         (rst),
      .eth_stream_i(eth_stream),
      .drop_o      (drop_o)
  );

endmodule
