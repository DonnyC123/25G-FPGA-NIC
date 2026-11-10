module async_fifo_top #(
  parameter int DATA_W     = 16,
  parameter int FIFO_DEPTH = 4
) (
  input  logic              axi_clk,
  input  logic              axi_rst,
  input  logic              eth_clk,
  input  logic              eth_rst,

  input  logic [DATA_W-1:0] data_i,
  input  logic              valid_i,
  output logic              ready_o,

  output logic [DATA_W-1:0] data_o,
  output logic              valid_o,
  input  logic              ready_i
);

  async_fifo #(
      .DATA_W    (DATA_W),
      .FIFO_DEPTH(FIFO_DEPTH)
  ) async_fifo_inst (
      .wr_clk (axi_clk),
      .wr_rst (axi_rst),
      .rd_clk (eth_clk),
      .rd_rst (eth_rst),
      .data_i (data_i),
      .valid_i(valid_i),
      .ready_o(ready_o),
      .data_o (data_o),
      .valid_o(valid_o),
      .ready_i(ready_i)
  );

endmodule
