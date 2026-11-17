module rx_csum
  import pcs_pkg::*;
  import parser_pkg::*;
(
  input  logic              clk,
  input  logic              rst,
  input  rx_eth_stream_t    eth_stream_i,
  output logic              csum_valid_o,
  output logic [CSUM_W-1:0] csum_o
);

  localparam int WORD_IDX_W = OFF_W - LAST_BYTES_W;
  localparam int SUM_W      = CSUM_W + $clog2(ETH_DATA_BYTES / CSUM_BYTES);

  localparam logic [OFF_W-1:0] START_POS = OFF_W'(RX_CSUM_START);

  logic [WORD_IDX_W-1:0]                     word_idx_d;
  logic [WORD_IDX_W-1:0]                     word_idx_q;
  logic [OFF_W-1:0]                          pos;
  logic                                      frame_end;

  logic [ETH_DATA_BYTES-1:0]                 start_mask;
  logic [ETH_DATA_BYTES-1:0]                 tail_mask;
  logic [ETH_DATA_BYTES-1:0]                 hold_tail_mask;

  logic [ETH_DATA_BYTES-1:0][BYTE_W-1:0]     hold_data_d;
  logic [ETH_DATA_BYTES-1:0][BYTE_W-1:0]     hold_data_q;
  logic [ETH_DATA_BYTES-1:0]                 hold_mask_d;
  logic [ETH_DATA_BYTES-1:0]                 hold_mask_q;
  logic                                      hold_valid_d;
  logic                                      hold_valid_q;

  logic [ETH_DATA_BYTES-1:0]                 hold_sum_mask;
  logic [ETH_DATA_BYTES-1:0]                 last_sum_mask;
  logic [SUM_W-1:0]                          hold_sum;
  logic [SUM_W-1:0]                          last_sum;

  logic [SUM_W:0]                            part_d;
  logic [SUM_W:0]                            part_q;
  logic                                      part_valid_q;
  logic                                      part_last_q;

  logic [CSUM_ACC_W-1:0]                     acc_d;
  logic [CSUM_ACC_W-1:0]                     acc_q;
  logic [CSUM_ACC_W-1:0]                     total_d;
  logic [CSUM_ACC_W-1:0]                     total_q;
  logic                                      done_d;
  logic                                      done_q;

  logic [CSUM_W-1:0]                         csum_q;
  logic                                      csum_valid_q;

  always_comb begin
    frame_end = eth_stream_i.valid && eth_stream_i.last;
    pos       = '0;

    for (int i = 0; i < ETH_DATA_BYTES; i++) begin
      pos               = {word_idx_q, LAST_BYTES_W'(i)};
      start_mask[i]     = pos >= START_POS;
      tail_mask[i]      = i < int'(eth_stream_i.last_bytes) - FCS_BYTES;
      hold_tail_mask[i] = !frame_end || i < int'(eth_stream_i.last_bytes) + ETH_DATA_BYTES - FCS_BYTES;
    end
  end

  always_comb begin
    word_idx_d   = word_idx_q;
    hold_data_d  = hold_data_q;
    hold_mask_d  = hold_mask_q;
    hold_valid_d = hold_valid_q;

    if (eth_stream_i.valid) begin
      hold_data_d  = eth_stream_i.data;
      hold_mask_d  = start_mask;
      hold_valid_d = !eth_stream_i.last;

      if (eth_stream_i.last) begin
        word_idx_d = '0;
      end else if (word_idx_q != '1) begin
        word_idx_d = word_idx_q + 1'b1;
      end
    end
  end

  always_comb begin
    hold_sum_mask = '0;
    last_sum_mask = '0;

    if (eth_stream_i.valid && hold_valid_q) begin
      hold_sum_mask = hold_mask_q & hold_tail_mask;
    end

    if (frame_end) begin
      last_sum_mask = start_mask & tail_mask;
    end
  end

  csum_word #(
      .BYTES(ETH_DATA_BYTES)
  ) hold_csum_word_inst (
      .data_i(hold_data_q),
      .mask_i(hold_sum_mask),
      .sum_o (hold_sum)
  );

  csum_word #(
      .BYTES(ETH_DATA_BYTES)
  ) last_csum_word_inst (
      .data_i(eth_stream_i.data),
      .mask_i(last_sum_mask),
      .sum_o (last_sum)
  );

  always_comb begin
    part_d = (SUM_W + 1)'(hold_sum) + (SUM_W + 1)'(last_sum);
  end

  always_comb begin
    acc_d   = acc_q;
    total_d = total_q;
    done_d  = 1'b0;

    if (part_valid_q) begin
      acc_d = acc_q + CSUM_ACC_W'(part_q);
      if (part_last_q) begin
        done_d  = 1'b1;
        total_d = acc_d;
        acc_d   = '0;
      end
    end
  end

  always_ff @(posedge clk) begin
    if (rst) begin
      word_idx_q   <= '0;
      hold_valid_q <= 1'b0;
      part_valid_q <= 1'b0;
      acc_q        <= '0;
      done_q       <= 1'b0;
      csum_valid_q <= 1'b0;
    end else begin
      word_idx_q   <= word_idx_d;
      hold_valid_q <= hold_valid_d;
      part_valid_q <= eth_stream_i.valid;
      acc_q        <= acc_d;
      done_q       <= done_d;
      csum_valid_q <= done_q;
    end
  end

  always_ff @(posedge clk) begin
    hold_data_q <= hold_data_d;
    hold_mask_q <= hold_mask_d;
    part_q      <= part_d;
    part_last_q <= frame_end;
    total_q     <= total_d;
    csum_q      <= csum_fold(total_q);
  end

  assign csum_valid_o = csum_valid_q;
  assign csum_o       = csum_q;

endmodule
