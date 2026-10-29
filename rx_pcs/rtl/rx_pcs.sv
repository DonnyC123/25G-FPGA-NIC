module rx_pcs
  import pcs_pkg::*;
#(
  parameter int DIN_W        = 64,
  parameter int GOOD_COUNT   = 64,
  parameter int BAD_COUNT    = 16,
  parameter int BITSLIP_WAIT = 40
) (
  input  logic             clk,
  input  logic             rst,
  input  logic [DIN_W-1:0] raw_data_i,
  input  logic             raw_valid_i,

  output logic             locked_o,
  output logic             bitslip_o,

  output rx_eth_stream_t   eth_stream_o
);

  pcs_66b_block_t block_sync_pcs_block;
  logic           block_sync_valid;

  pcs_66b_block_t descrambled_pcs_block;
  logic           descrambled_valid;

  block_sync #(
      .DIN_W     (DIN_W),
      .DOUT_W    (PCS_BLOCK_W),
      .REG_OUTPUT(1)
  ) block_sync_inst (
      .clk    (clk),
      .rst    (rst),
      .data_i (raw_data_i),
      .valid_i(raw_valid_i),
      .data_o (block_sync_pcs_block),
      .valid_o(block_sync_valid)
  );

  descrambler #(
      .REG_OUTPUT(1)
  ) descrambler_inst (
      .clk                    (clk),
      .rst                    (rst),
      .pcs_block_i            (block_sync_pcs_block),
      .valid_i                (block_sync_valid),
      .descrambled_pcs_block_o(descrambled_pcs_block),
      .valid_o                (descrambled_valid)
  );

  alignment_finder #(
      .GOOD_COUNT  (GOOD_COUNT),
      .BAD_COUNT   (BAD_COUNT),
      .BITSLIP_WAIT(BITSLIP_WAIT)
  ) alignment_finder_inst (
      .clk         (clk),
      .rst         (rst),
      .sync_i      (block_sync_pcs_block.sync),
      .sync_valid_i(block_sync_valid),
      .aligned_o   (locked_o),
      .bitslip_o   (bitslip_o)
  );

  pcs_decoder pcs_decoder_inst (
      .clk                (clk),
      .rst                (rst),
      .valid_i            (descrambled_valid),
      .pcs_block_i        (descrambled_pcs_block),
      .aligned_i          (locked_o),
      .eth_stream_o       (eth_stream_o),
      .pcs_decoder_error_o()
  );

endmodule
