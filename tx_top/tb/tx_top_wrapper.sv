module tx_top_wrapper
  import pcs_pkg::*;
#(
  parameter int AXI_DATA_W      = 256,
  parameter int FIFO_DEPTH      = 64,
  parameter int MIN_FRAME_BYTES = 60
) (
  input  logic                     axi_clk,
  input  logic                     axi_rst,
  input  logic                     eth_clk,
  input  logic                     eth_rst,

  output logic [PCS_PAYLOAD_W-1:0] raw_data_o,
  output logic                     raw_valid_o
);

  axi_stream_if #(.DATA_W(AXI_DATA_W)) s_axi ();

  tx_top #(
      .FIFO_DEPTH     (FIFO_DEPTH),
      .MIN_FRAME_BYTES(MIN_FRAME_BYTES)
  ) tx_top_inst (
      .axi_clk    (axi_clk),
      .axi_rst    (axi_rst),
      .eth_clk    (eth_clk),
      .eth_rst    (eth_rst),
      .s_axi      (s_axi),
      .raw_data_o (raw_data_o),
      .raw_valid_o(raw_valid_o)
  );

endmodule
