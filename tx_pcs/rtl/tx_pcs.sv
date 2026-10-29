module tx_pcs
  import pcs_pkg::*;
#(
  parameter int MIN_FRAME_BYTES  = 60,
  parameter int SCRAMBLER_BYPASS = 0,
  parameter int DOUT_W           = 64
) (
  input  logic                  clk,
  input  logic                  rst,
         tx_eth_stream_if.slave tx_stream_i,

  output logic [DOUT_W-1:0]     raw_data_o,
  output logic                  raw_valid_o
);

  pcs_66b_block_t framed_pcs_block;
  logic           framed_valid;

  pcs_66b_block_t scrambled_pcs_block;
  logic           scrambled_valid;

  logic           gearbox_ready;

  tx_framer #(
      .MIN_FRAME_BYTES(MIN_FRAME_BYTES)
  ) tx_framer_inst (
      .clk          (clk),
      .rst          (rst),
      .tx_stream_i  (tx_stream_i),
      .out_ready_i  (gearbox_ready),
      .out_data_o   (framed_pcs_block.payload),
      .out_control_o(framed_pcs_block.sync),
      .out_valid_o  (framed_valid)
  );

  scrambler #(
      .BYPASS    (SCRAMBLER_BYPASS),
      .REG_OUTPUT(0)
  ) scrambler_inst (
      .clk                  (clk),
      .rst                  (rst),
      .pcs_block_i          (framed_pcs_block),
      .valid_i              (framed_valid),
      .scrambled_pcs_block_o(scrambled_pcs_block),
      .valid_o              (scrambled_valid)
  );

  tx_gearbox #(
      .DIN_W     (PCS_BLOCK_W),
      .DOUT_W    (DOUT_W),
      .REG_OUTPUT(1)
  ) tx_gearbox_inst (
      .clk    (clk),
      .rst    (rst),
      .data_i (scrambled_pcs_block),
      .valid_i(scrambled_valid),
      .ready_o(gearbox_ready),
      .data_o (raw_data_o),
      .valid_o(raw_valid_o)
  );

endmodule
