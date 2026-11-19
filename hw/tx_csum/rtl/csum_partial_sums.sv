module csum_partial_sums
  import csum_pkg::*;
  import tx_meta_pkg::*;
#(
  parameter int WORD_W = CSUM_W + $clog2(TX_META_BYTES / CSUM_BYTES)
) (
  input  logic                                     clk,
  input  logic                                     rst,
         axi_stream_if.monitor                     s_axi,
  input  logic                 [TX_META_BYTES-1:0] csum_mask_i,
  input  tx_meta_t                                 meta_i,

  output logic                 [WORD_W-1:0]        word_o,
  output logic                                     last_o,
  output tx_meta_t                                 meta_o,
  output logic                 [TX_OFF_W-1:0]      len_o,
  output logic                                     valid_o
);

  localparam int MASK_W = s_axi.MASK_W;

  logic                    accept;
  logic     [WORD_W-1:0]   word_sum;
  logic     [TX_OFF_W-1:0] pos_d;
  logic     [TX_OFF_W-1:0] pos_q;

  logic                    valid_q;
  logic     [WORD_W-1:0]   word_d;
  logic     [WORD_W-1:0]   word_q;
  logic                    last_d;
  logic                    last_q;
  tx_meta_t                meta_d;
  tx_meta_t                meta_q;
  logic     [TX_OFF_W-1:0] len_d;
  logic     [TX_OFF_W-1:0] len_q;

  csum_word #(
      .BYTES(MASK_W)
  ) csum_word_inst (
      .data_i(s_axi.data),
      .mask_i(csum_mask_i),
      .sum_o (word_sum)
  );

  always_comb begin
    accept = s_axi.valid && s_axi.ready;
    word_d = word_sum;
    last_d = s_axi.last;
    meta_d = meta_i;
    len_d  = pos_q + TX_OFF_W'($countones(s_axi.mask));

    pos_d  = pos_q;
    if (accept) begin
      pos_d = pos_q + TX_OFF_W'($unsigned(MASK_W));
      if (s_axi.last) begin
        pos_d = '0;
      end
    end
  end

  always_ff @(posedge clk) begin
    if (rst) begin
      pos_q   <= '0;
      valid_q <= 1'b0;
      word_q  <= 'x;
      last_q  <= 'x;
      meta_q  <= 'x;
      len_q   <= 'x;
    end else begin
      pos_q   <= pos_d;
      valid_q <= accept;
      word_q  <= word_d;
      last_q  <= last_d;
      meta_q  <= meta_d;
      len_q   <= len_d;
    end
  end

  always_comb begin
    word_o  = word_q;
    last_o  = last_q;
    meta_o  = meta_q;
    len_o   = len_q;
    valid_o = valid_q;
  end

endmodule
