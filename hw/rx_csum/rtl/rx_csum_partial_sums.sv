module rx_csum_partial_sums
  import pcs_pkg::*;
  import parser_pkg::*;
  import csum_pkg::*;
#(
  parameter int WORD_W = CSUM_W + $clog2(ETH_DATA_BYTES / CSUM_BYTES)
) (
  input  logic                        clk,
  input  logic                        rst,
  input  rx_eth_stream_t              eth_stream_i,

  output logic           [WORD_W-1:0] word_o,
  output logic                        last_o,
  output logic                        drop_o,
  output logic                        valid_o
);

  localparam rx_off_t START_POS = RX_OFF_W'(RX_CSUM_START_OFF);
  localparam int      POS_W     = LAST_BYTES_W + 1;

  logic                                          frame_end;
  rx_off_t                                       pos;
  logic         [ETH_DATA_BYTES-1:0]             start_mask;
  logic         [ETH_DATA_BYTES-1:0]             tail_mask;
  logic         [ETH_DATA_BYTES-1:0]             hold_tail_mask;
  logic                                          sum_valid;
  logic         [ETH_DATA_BYTES-1:0]             sum_mask;
  logic         [WORD_W-1:0]                     word_sum;

  rx_word_idx_t                                  word_idx_d;
  rx_word_idx_t                                  word_idx_q;
  logic         [ETH_DATA_BYTES-1:0][BYTE_W-1:0] hold_data_d;
  logic         [ETH_DATA_BYTES-1:0][BYTE_W-1:0] hold_data_q;
  logic         [ETH_DATA_BYTES-1:0]             hold_mask_d;
  logic         [ETH_DATA_BYTES-1:0]             hold_mask_q;
  logic                                          hold_last_d;
  logic                                          hold_last_q;
  logic                                          hold_valid_d;
  logic                                          hold_valid_q;

  always_comb begin
    frame_end = eth_stream_i.valid && eth_stream_i.last;
    pos       = '0;

    for (int i = 0; i < ETH_DATA_BYTES; i++) begin
      pos               = {word_idx_q, LAST_BYTES_W'(i)};
      start_mask[i]     = pos >= START_POS;
      tail_mask[i]      = POS_W'(i + FCS_BYTES) < POS_W'(eth_stream_i.last_bytes);
      hold_tail_mask[i] = POS_W'(i) < POS_W'(eth_stream_i.last_bytes) + POS_W'(ETH_DATA_BYTES - FCS_BYTES);
    end
  end

  csum_word #(
      .BYTES(ETH_DATA_BYTES)
  ) csum_word_inst (
      .data_i(hold_data_q),
      .mask_i(sum_mask),
      .sum_o (word_sum)
  );

  always_comb begin
    sum_valid = hold_valid_q && (eth_stream_i.valid || hold_last_q);
    sum_mask  = hold_mask_q;
    if (frame_end && !hold_last_q) begin
      sum_mask = hold_mask_q & hold_tail_mask;
    end

    word_idx_d   = word_idx_q;
    hold_data_d  = hold_data_q;
    hold_mask_d  = hold_mask_q;
    hold_last_d  = hold_last_q;
    hold_valid_d = hold_valid_q && !sum_valid;

    if (eth_stream_i.valid) begin
      hold_data_d  = {>>{eth_stream_i.data}};
      hold_mask_d  = start_mask;
      hold_last_d  = eth_stream_i.last;
      hold_valid_d = 1'b1;
      if (word_idx_q != '1) begin
        word_idx_d = word_idx_q + 1'b1;
      end
      if (eth_stream_i.last) begin
        hold_mask_d = start_mask & tail_mask;
        word_idx_d  = '0;
      end
    end

    if (eth_stream_i.drop) begin
      word_idx_d   = '0;
      hold_valid_d = 1'b0;
    end
  end

  always_ff @(posedge clk) begin
    if (rst) begin
      word_idx_q   <= '0;
      hold_valid_q <= 1'b0;
      hold_data_q  <= 'x;
      hold_mask_q  <= 'x;
      hold_last_q  <= 'x;
    end else begin
      word_idx_q   <= word_idx_d;
      hold_valid_q <= hold_valid_d;
      hold_data_q  <= hold_data_d;
      hold_mask_q  <= hold_mask_d;
      hold_last_q  <= hold_last_d;
    end
  end

  always_comb begin
    word_o  = word_sum;
    last_o  = hold_last_q;
    drop_o  = eth_stream_i.drop;
    valid_o = sum_valid;
  end

endmodule
