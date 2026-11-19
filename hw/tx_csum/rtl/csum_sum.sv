module csum_sum
  import csum_pkg::*;
  import tx_meta_pkg::*;
(
  input  logic                                    clk,
  input  logic                                    rst,
         axi_stream_if.monitor                    s_axi,
  input  logic                [TX_META_BYTES-1:0] csum_mask_i,
  input  tx_meta_t                                meta_i,

  output csum_result_t                            result_o,
  output logic                                    result_valid_o
);

  localparam int MASK_W = s_axi.MASK_W;
  localparam int WORD_W = CSUM_W + $clog2(MASK_W / CSUM_BYTES);

  logic     [WORD_W-1:0]       beat_word;
  logic                        beat_last;
  tx_meta_t                    beat_meta;
  logic     [TX_OFF_W-1:0]     beat_len;
  logic                        beat_valid;

  logic     [CSUM_ACCUM_W-1:0] frame_total;
  tx_meta_t                    frame_meta;
  logic     [TX_OFF_W-1:0]     frame_len;
  logic                        frame_valid;

  csum_partial_sums #(
      .WORD_W(WORD_W)
  ) csum_partial_sums_inst (
      .clk        (clk),
      .rst        (rst),
      .s_axi      (s_axi),
      .csum_mask_i(csum_mask_i),
      .meta_i     (meta_i),
      .word_o     (beat_word),
      .last_o     (beat_last),
      .meta_o     (beat_meta),
      .len_o      (beat_len),
      .valid_o    (beat_valid)
  );

  csum_accum #(
      .WORD_W(WORD_W)
  ) csum_accum_inst (
      .clk    (clk),
      .rst    (rst),
      .word_i (beat_word),
      .last_i (beat_last),
      .meta_i (beat_meta),
      .len_i  (beat_len),
      .valid_i(beat_valid),
      .total_o(frame_total),
      .meta_o (frame_meta),
      .len_o  (frame_len),
      .valid_o(frame_valid)
  );

  csum_finish csum_finish_inst (
      .clk           (clk),
      .rst           (rst),
      .total_i       (frame_total),
      .meta_i        (frame_meta),
      .len_i         (frame_len),
      .valid_i       (frame_valid),
      .result_o      (result_o),
      .result_valid_o(result_valid_o)
  );

endmodule
