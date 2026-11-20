module rx_csum
  import pcs_pkg::*;
  import parser_pkg::*;
  import csum_pkg::*;
(
  input  logic              clk,
  input  logic              rst,
  input  rx_eth_stream_t    eth_stream_i,
  output logic              csum_valid_o,
  output logic [CSUM_W-1:0] csum_o
);

  localparam int WORD_W = CSUM_W + $clog2(ETH_DATA_BYTES / CSUM_BYTES);

  logic [WORD_W-1:0]       partial_word;
  logic                    partial_last;
  logic                    partial_drop;
  logic                    partial_valid;
  logic [WORD_W-1:0]       partial_word_q;
  logic                    partial_last_q;
  logic                    partial_drop_q;
  logic                    partial_valid_q;

  logic [CSUM_ACCUM_W-1:0] frame_total;
  logic                    frame_valid;
  logic [CSUM_ACCUM_W-1:0] frame_total_q;
  logic                    frame_valid_q;

  rx_csum_partial_sums #(
      .WORD_W(WORD_W)
  ) rx_csum_partial_sums_inst (
      .clk         (clk),
      .rst         (rst),
      .eth_stream_i(eth_stream_i),
      .word_o      (partial_word),
      .last_o      (partial_last),
      .drop_o      (partial_drop),
      .valid_o     (partial_valid)
  );

  data_status_pipeline #(
      .DATA_W    (WORD_W + 1),
      .STATUS_W  (2),
      .PIPE_DEPTH(RX_CSUM_SUM_STAGES)
  ) partial_pipeline_inst (
      .clk     (clk),
      .rst     (rst),
      .data_i  ({partial_word, partial_last}),
      .status_i({partial_valid, partial_drop}),
      .data_o  ({partial_word_q, partial_last_q}),
      .status_o({partial_valid_q, partial_drop_q})
  );

  rx_csum_accum #(
      .WORD_W(WORD_W)
  ) rx_csum_accum_inst (
      .clk    (clk),
      .rst    (rst),
      .word_i (partial_word_q),
      .last_i (partial_last_q),
      .drop_i (partial_drop_q),
      .valid_i(partial_valid_q),
      .total_o(frame_total),
      .valid_o(frame_valid)
  );

  data_status_pipeline #(
      .DATA_W    (CSUM_ACCUM_W),
      .STATUS_W  (1),
      .PIPE_DEPTH(RX_CSUM_ACCUM_STAGES)
  ) frame_pipeline_inst (
      .clk     (clk),
      .rst     (rst),
      .data_i  (frame_total),
      .status_i(frame_valid),
      .data_o  (frame_total_q),
      .status_o(frame_valid_q)
  );

  rx_csum_finish rx_csum_finish_inst (
      .total_i     (frame_total_q),
      .valid_i     (frame_valid_q),
      .csum_o      (csum_o),
      .csum_valid_o(csum_valid_o)
  );

endmodule
