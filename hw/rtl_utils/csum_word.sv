module csum_word
  import pcs_pkg::BYTE_W;
  import csum_pkg::CSUM_W;
  import csum_pkg::CSUM_BYTES;
#(
  parameter  int BYTES = 8,
  localparam int WORDS = BYTES / CSUM_BYTES,
  localparam int SUM_W = CSUM_W + $clog2(WORDS)
) (
  input  logic [BYTES-1:0][BYTE_W-1:0] data_i,
  input  logic [BYTES-1:0]             mask_i,
  output logic [SUM_W-1:0]             sum_o
);

  always_comb begin
    sum_o = '0;
    for (int i = 0; i < WORDS; i++) begin
      sum_o += SUM_W'({mask_i[2*i] ? data_i[2*i] : BYTE_W'(0), mask_i[2*i+1] ? data_i[2*i+1] : BYTE_W'(0)});
    end
  end

endmodule
