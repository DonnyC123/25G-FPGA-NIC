module tx_framer_top
  import pcs_pkg::*;
#(
  parameter int MIN_FRAME_BYTES = 60
) (
  input  logic                     clk,
  input  logic                     rst,
  input  logic                     out_ready_i,
  output logic [PCS_PAYLOAD_W-1:0] out_data_o,
  output logic [PCS_SYNC_W-1:0]    out_control_o,
  output logic                     out_valid_o
);

  tx_eth_stream_if #(.DATA_W(PCS_PAYLOAD_W)) tx_stream_i ();

  tx_framer #(
      .MIN_FRAME_BYTES(MIN_FRAME_BYTES)
  ) tx_framer_inst (
      .clk          (clk),
      .rst          (rst),
      .tx_stream_i  (tx_stream_i),
      .out_ready_i  (out_ready_i),
      .out_data_o   (out_data_o),
      .out_control_o(out_control_o),
      .out_valid_o  (out_valid_o)
  );

endmodule
