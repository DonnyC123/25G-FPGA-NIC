module rx_csum_accum
  import pcs_pkg::ETH_DATA_BYTES;
  import csum_pkg::*;
#(
  parameter int WORD_W = CSUM_W + $clog2(ETH_DATA_BYTES / CSUM_BYTES)
) (
  input  logic                    clk,
  input  logic                    rst,
  input  logic [WORD_W-1:0]       word_i,
  input  logic                    last_i,
  input  logic                    drop_i,
  input  logic                    valid_i,

  output logic [CSUM_ACCUM_W-1:0] total_o,
  output logic                    valid_o
);

  logic [CSUM_ACCUM_W-1:0] acc_sum;
  logic [CSUM_ACCUM_W-1:0] acc_d;
  logic [CSUM_ACCUM_W-1:0] acc_q;

  always_comb begin
    acc_sum = acc_q + CSUM_ACCUM_W'(word_i);

    acc_d   = acc_q;
    if (valid_i) begin
      acc_d = acc_sum;
      if (last_i) begin
        acc_d = '0;
      end
    end
    if (drop_i) begin
      acc_d = '0;
    end
  end

  always_ff @(posedge clk) begin
    if (rst) begin
      acc_q <= '0;
    end else begin
      acc_q <= acc_d;
    end
  end

  always_comb begin
    total_o = acc_sum;
    valid_o = valid_i && last_i;
  end

endmodule
