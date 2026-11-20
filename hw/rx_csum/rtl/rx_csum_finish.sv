module rx_csum_finish
  import csum_pkg::*;
(
  input  logic [CSUM_ACCUM_W-1:0] total_i,
  input  logic                    valid_i,

  output logic [CSUM_W-1:0]       csum_o,
  output logic                    csum_valid_o
);

  always_comb begin
    csum_o       = ones_sum_fold(total_i);
    csum_valid_o = valid_i;
  end

endmodule
