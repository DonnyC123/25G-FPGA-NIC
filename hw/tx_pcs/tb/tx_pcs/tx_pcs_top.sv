module tx_pcs_top
  import pcs_pkg::*;
#(
  parameter int MIN_FRAME_BYTES = 60
) (
  input  logic                     clk,
  input  logic                     rst,
  output logic [PCS_PAYLOAD_W-1:0] raw_data_o,
  output logic                     raw_valid_o
);

  tx_eth_stream_if #(.DATA_W(PCS_PAYLOAD_W)) tx_stream_i ();

  tx_pcs #(
      .MIN_FRAME_BYTES(MIN_FRAME_BYTES)
  ) tx_pcs_inst (
      .clk        (clk),
      .rst        (rst),
      .tx_stream_i(tx_stream_i),
      .raw_data_o (raw_data_o),
      .raw_valid_o(raw_valid_o)
  );

endmodule
