module csum_finish
  import csum_pkg::*;
  import tx_meta_pkg::*;
  import pcs_pkg::BYTE_W;
(
  input  logic                            clk,
  input  logic                            rst,
  input  logic         [CSUM_ACCUM_W-1:0] total_i,
  input  tx_meta_t                        meta_i,
  input  logic         [TX_OFF_W-1:0]     len_i,
  input  logic                            valid_i,

  output csum_result_t                    result_o,
  output logic                            result_valid_o
);

  logic         [CSUM_W-1:0]   folded;
  logic         [CSUM_W-1:0]   aligned;
  logic         [CSUM_W-1:0]   csum;
  logic         [TX_OFF_W-1:0] csum_pos;
  logic         [TX_OFF_W:0]   csum_end;
  logic                        fits;

  csum_result_t                result_d;
  csum_result_t                result_q;
  logic                        result_valid_q;

  always_comb begin
    folded = ones_sum_fold(total_i);

    aligned = folded;
    if (meta_i.csum_start[0]) begin
      aligned = {<<BYTE_W{folded}};
    end

    csum = ~aligned;
    if (csum == '0) begin
      csum = '1;
    end

    csum_pos = TX_OFF_W'(meta_i.csum_start) + TX_OFF_W'(meta_i.csum_offset);
    csum_end = {1'b0, csum_pos} + (TX_OFF_W + 1)'(CSUM_BYTES);
    fits     = {1'b0, len_i} >= csum_end;

    result_d.l4_en   = meta_i.csum && fits;
    result_d.l4_pos  = csum_pos;
    result_d.l4_csum = csum;
  end

  always_ff @(posedge clk) begin
    if (rst) begin
      result_valid_q <= 1'b0;
      result_q       <= 'x;
    end else begin
      result_valid_q <= valid_i;
      result_q       <= result_d;
    end
  end

  always_comb begin
    result_o       = result_q;
    result_valid_o = result_valid_q;
  end

endmodule
