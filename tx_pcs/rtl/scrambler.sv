module scrambler
  import pcs_pkg::*;
#(
  parameter int BYPASS     = 0,
  parameter int REG_OUTPUT = 1
) (
  input  logic           clk,
  input  logic           rst,
  input  pcs_66b_block_t pcs_block_i,
  input  logic           valid_i,
  output pcs_66b_block_t scrambled_pcs_block_o,
  output logic           valid_o
);
  localparam int POLY_EXP_1 = 39;
  localparam int POLY_EXP_2 = 58;
  localparam int BUFFER_W   = POLY_EXP_2;
  localparam int WINDOW_W   = PCS_PAYLOAD_W + BUFFER_W;

  logic           [BUFFER_W-1:0] buffer_d;
  logic           [BUFFER_W-1:0] buffer_q;
  logic           [WINDOW_W-1:0] window;
  pcs_66b_block_t                scrambled_pcs_block;

  always_comb begin
    window = WINDOW_W'(buffer_q);
    for (int i = 0; i < PCS_PAYLOAD_W; i++) begin
      window[BUFFER_W+i] = pcs_block_i.payload[i]
                         ^ window[BUFFER_W+i-POLY_EXP_1]
                         ^ window[BUFFER_W+i-POLY_EXP_2];
    end

    buffer_d = buffer_q;
    if (valid_i) begin
      buffer_d = window[WINDOW_W-1-:BUFFER_W];
    end

    scrambled_pcs_block.sync    = pcs_block_i.sync;
    scrambled_pcs_block.payload = window[WINDOW_W-1-:PCS_PAYLOAD_W];
    if (BYPASS != 0) begin
      scrambled_pcs_block.payload = pcs_block_i.payload;
    end
  end

  always_ff @(posedge clk) begin
    if (rst) begin
      buffer_q <= '1;
    end else begin
      buffer_q <= buffer_d;
    end
  end

  data_status_pipeline #(
      .DATA_W    (PCS_BLOCK_W),
      .STATUS_W  (1),
      .PIPE_DEPTH(REG_OUTPUT)
  ) data_status_pipeline_inst (
      .clk     (clk),
      .rst     (rst),
      .data_i  (scrambled_pcs_block),
      .status_i(valid_i),
      .data_o  (scrambled_pcs_block_o),
      .status_o(valid_o)
  );

endmodule
