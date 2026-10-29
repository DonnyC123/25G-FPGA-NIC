module descrambler
  import pcs_pkg::*;
#(
  parameter int REG_OUTPUT = 1
) (
  input  logic           clk,
  input  logic           rst,
  input  pcs_66b_block_t pcs_block_i,
  input  logic           valid_i,
  output pcs_66b_block_t descrambled_pcs_block_o,
  output logic           valid_o
);
  localparam int POLY_EXP_1 = 39;
  localparam int POLY_EXP_2 = 58;
  localparam int BUFFER_W   = POLY_EXP_2;
  localparam int WINDOW_W   = PCS_PAYLOAD_W + BUFFER_W;

  logic           [BUFFER_W-1:0] buffer_d;
  logic           [BUFFER_W-1:0] buffer_q;
  logic           [WINDOW_W-1:0] window;
  pcs_66b_block_t                descrambled_pcs_block;

  always_comb begin
    window   = {pcs_block_i.payload, buffer_q};

    buffer_d = buffer_q;
    if (valid_i) begin
      buffer_d = window[WINDOW_W-1-:BUFFER_W];
    end

    descrambled_pcs_block.sync = pcs_block_i.sync;
    for (int i = 0; i < PCS_PAYLOAD_W; i++) begin
      descrambled_pcs_block.payload[i] = window[BUFFER_W+i]
                                       ^ window[BUFFER_W+i-POLY_EXP_1]
                                       ^ window[BUFFER_W+i-POLY_EXP_2];
    end
  end

  always_ff @(posedge clk) begin
    buffer_q <= buffer_d;
  end

  data_status_pipeline #(
      .DATA_W    (PCS_BLOCK_W),
      .STATUS_W  (1),
      .PIPE_DEPTH(REG_OUTPUT)
  ) u_data_status_pipeline (
      .clk     (clk),
      .rst     (rst),
      .data_i  (descrambled_pcs_block),
      .status_i(valid_i),
      .data_o  (descrambled_pcs_block_o),
      .status_o(valid_o)
  );

endmodule
