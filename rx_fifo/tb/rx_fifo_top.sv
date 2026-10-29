module rx_fifo_top
  import pcs_pkg::*;
#(
  parameter int M_DATA_W   = 256,
  parameter int FIFO_DEPTH = 64
) (
  input  logic                     eth_clk,
  input  logic                     eth_rst,
  input  logic                     axi_clk,
  input  logic                     axi_rst,
  input  logic [ETH_DATA_W-1:0]    data_i,
  input  logic [LAST_BYTES_W-1:0]  last_bytes_i,
  input  logic                     valid_i,
  input  logic                     last_i,
  input  logic                     drop_i,
  output logic                     cancel_o
);

  axi_stream_if #(.DATA_W(M_DATA_W)) m_axi ();

  rx_eth_stream_t eth_stream;

  always_comb begin
    eth_stream.data       = data_i;
    eth_stream.last_bytes = last_bytes_i;
    eth_stream.valid      = valid_i;
    eth_stream.last       = last_i;
    eth_stream.drop       = drop_i;
  end

  rx_fifo_ctrl #(
      .FIFO_DEPTH(FIFO_DEPTH)
  ) rx_fifo_ctrl_inst (
      .s_clk       (eth_clk),
      .s_rst       (eth_rst),
      .m_clk       (axi_clk),
      .m_rst       (axi_rst),
      .eth_stream_i(eth_stream),
      .cancel_o    (cancel_o),
      .m_axi       (m_axi)
  );

endmodule
