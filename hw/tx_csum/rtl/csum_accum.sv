module csum_accum
  import csum_pkg::*;
  import tx_meta_pkg::*;
#(
  parameter int WORD_W = CSUM_W + $clog2(TX_META_BYTES / CSUM_BYTES)
) (
  input  logic                        clk,
  input  logic                        rst,
  input  logic     [WORD_W-1:0]       word_i,
  input  logic                        last_i,
  input  tx_meta_t                    meta_i,
  input  logic     [TX_OFF_W-1:0]     len_i,
  input  logic                        valid_i,

  output logic     [CSUM_ACCUM_W-1:0] total_o,
  output tx_meta_t                    meta_o,
  output logic     [TX_OFF_W-1:0]     len_o,
  output logic                        valid_o
);

  logic     [CSUM_ACCUM_W-1:0] acc_sum;
  logic     [CSUM_ACCUM_W-1:0] acc_d;
  logic     [CSUM_ACCUM_W-1:0] acc_q;

  logic                        valid_d;
  logic                        valid_q;
  logic     [CSUM_ACCUM_W-1:0] total_d;
  logic     [CSUM_ACCUM_W-1:0] total_q;
  tx_meta_t                    meta_d;
  tx_meta_t                    meta_q;
  logic     [TX_OFF_W-1:0]     len_d;
  logic     [TX_OFF_W-1:0]     len_q;

  always_comb begin
    acc_sum = acc_q + CSUM_ACCUM_W'(word_i);
    valid_d = valid_i && last_i;
    total_d = acc_sum;
    meta_d  = meta_i;
    len_d   = len_i;

    acc_d   = acc_q;
    if (valid_i) begin
      acc_d = acc_sum;
      if (last_i) begin
        acc_d = '0;
      end
    end
  end

  always_ff @(posedge clk) begin
    if (rst) begin
      acc_q   <= '0;
      valid_q <= 1'b0;
      total_q <= 'x;
      meta_q  <= 'x;
      len_q   <= 'x;
    end else begin
      acc_q   <= acc_d;
      valid_q <= valid_d;
      total_q <= total_d;
      meta_q  <= meta_d;
      len_q   <= len_d;
    end
  end

  always_comb begin
    total_o = total_q;
    meta_o  = meta_q;
    len_o   = len_q;
    valid_o = valid_q;
  end

endmodule
