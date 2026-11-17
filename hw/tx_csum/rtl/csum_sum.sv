module csum_sum
  import parser_pkg::OFF_W;
  import parser_pkg::CSUM_W;
  import parser_pkg::CSUM_BYTES;
  import parser_pkg::CSUM_ACC_W;
  import parser_pkg::csum_result_t;
  import parser_pkg::csum_fold;
  import tx_meta_pkg::tx_meta_t;
  import pcs_pkg::BYTE_W;
#(
  parameter  int DATA_W = 256,
  localparam int MASK_W = DATA_W / BYTE_W
) (
  input  logic              clk,
  input  logic              rst,
  input  logic [DATA_W-1:0] data_i,
  input  logic [MASK_W-1:0] mask_i,
  input  logic [MASK_W-1:0] csum_mask_i,
  input  logic              last_i,
  input  logic              accept_i,
  input  tx_meta_t          meta_i,

  output csum_result_t      result_o,
  output logic              result_valid_o
);

  localparam int HALF_WORDS = MASK_W / CSUM_BYTES;
  localparam int WORD_SUM_W = CSUM_W + $clog2(HALF_WORDS);
  localparam int ACC_W      = CSUM_ACC_W;

  logic [OFF_W-1:0]      pos_d;
  logic [OFF_W-1:0]      pos_q;

  logic [WORD_SUM_W-1:0] word_sum;
  logic [WORD_SUM_W-1:0] word_d;
  logic [WORD_SUM_W-1:0] word_q;
  logic                  word_valid_q;
  logic                  word_last_q;
  tx_meta_t              word_meta_q;
  logic [OFF_W-1:0]      word_len_q;

  logic [ACC_W-1:0]      acc_d;
  logic [ACC_W-1:0]      acc_q;
  logic [ACC_W-1:0]      total_d;
  logic [ACC_W-1:0]      total_q;
  logic                  done_d;
  logic                  done_q;
  tx_meta_t              done_meta_q;
  logic [OFF_W-1:0]      done_len_q;

  logic [CSUM_W-1:0]     sum;
  logic [CSUM_W-1:0]     csum;
  logic [OFF_W-1:0]      csum_pos;
  csum_result_t          result_d;
  csum_result_t          result_q;
  logic                  result_valid_q;

  csum_word #(
      .BYTES(MASK_W)
  ) csum_word_inst (
      .data_i(data_i),
      .mask_i(csum_mask_i),
      .sum_o (word_sum)
  );

  always_comb begin
    word_d = word_sum;

    pos_d = pos_q;
    if (accept_i) begin
      pos_d = last_i ? '0 : pos_q + OFF_W'(MASK_W);
    end
  end

  always_ff @(posedge clk) begin
    if (rst) begin
      pos_q        <= '0;
      word_valid_q <= 1'b0;
    end else begin
      pos_q        <= pos_d;
      word_valid_q <= accept_i;
    end
  end

  always_ff @(posedge clk) begin
    if (accept_i) begin
      word_q      <= word_d;
      word_last_q <= last_i;
      word_meta_q <= meta_i;
      word_len_q  <= pos_q + OFF_W'($countones(mask_i));
    end
  end

  always_comb begin
    acc_d   = acc_q;
    total_d = total_q;
    done_d  = 1'b0;
    if (word_valid_q) begin
      acc_d = acc_q + ACC_W'(word_q);
      if (word_last_q) begin
        done_d  = 1'b1;
        total_d = acc_d;
        acc_d   = '0;
      end
    end
  end

  always_ff @(posedge clk) begin
    if (rst) begin
      acc_q  <= '0;
      done_q <= 1'b0;
    end else begin
      acc_q  <= acc_d;
      done_q <= done_d;
    end
  end

  always_ff @(posedge clk) begin
    total_q <= total_d;
    if (done_d) begin
      done_meta_q <= word_meta_q;
      done_len_q  <= word_len_q;
    end
  end

  always_comb begin
    sum = csum_fold(total_q);
    if (done_meta_q.csum_start[0]) begin
      sum = {sum[BYTE_W-1:0], sum[CSUM_W-1-:BYTE_W]};
    end
    csum     = ~sum;
    csum_pos = OFF_W'(done_meta_q.csum_start) + OFF_W'(done_meta_q.csum_offset);

    result_d         = '0;
    result_d.l4_en   = done_meta_q.csum && done_len_q >= csum_pos + OFF_W'(CSUM_BYTES);
    result_d.l4_pos  = csum_pos;
    result_d.l4_csum = csum == '0 ? '1 : csum;
  end

  always_ff @(posedge clk) begin
    if (rst) begin
      result_valid_q <= 1'b0;
    end else begin
      result_valid_q <= done_q;
    end
  end

  always_ff @(posedge clk) begin
    if (done_q) begin
      result_q <= result_d;
    end
  end

  always_comb begin
    result_o       = result_q;
    result_valid_o = result_valid_q;
  end

endmodule
