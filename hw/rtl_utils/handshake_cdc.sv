module handshake_cdc #(
  parameter int DATA_W     = 32,
  parameter int SYNC_DEPTH = 2
) (
  input  logic              src_clk,
  input  logic              src_rst,
  input  logic [DATA_W-1:0] src_data_i,
  input  logic              src_valid_i,
  output logic              src_ready_o,

  input  logic              dst_clk,
  input  logic              dst_rst,
  output logic [DATA_W-1:0] dst_data_o,
  output logic              dst_valid_o
);

  logic [DATA_W-1:0] hold_d;
  logic [DATA_W-1:0] hold_q;
  logic              req_d;
  logic              req_q;
  logic              req_sync [SYNC_DEPTH];
  logic              ack_d;
  logic              ack_q;
  logic              ack_sync [SYNC_DEPTH];
  logic              take;

  always_comb begin
    src_ready_o = req_q == ack_sync[SYNC_DEPTH-1];
    take        = src_valid_i && src_ready_o;
    hold_d      = hold_q;
    req_d       = req_q;

    if (take) begin
      hold_d = src_data_i;
      req_d  = !req_q;
    end
  end

  always_ff @(posedge src_clk) begin
    if (src_rst) begin
      req_q <= 1'b0;
    end else begin
      req_q <= req_d;
    end
  end

  always_ff @(posedge src_clk) begin
    hold_q <= hold_d;
  end

  shift_reg #(
      .DATA_W    (1),
      .PIPE_DEPTH(SYNC_DEPTH)
  ) req_sync_inst (
      .clk   (dst_clk),
      .rst   (dst_rst),
      .data_i(req_q),
      .data_o(req_sync)
  );

  always_comb begin
    dst_valid_o = req_sync[SYNC_DEPTH-1] != ack_q;
    ack_d       = req_sync[SYNC_DEPTH-1];
  end

  always_ff @(posedge dst_clk) begin
    if (dst_rst) begin
      ack_q <= 1'b0;
    end else begin
      ack_q <= ack_d;
    end
  end

  shift_reg #(
      .DATA_W    (1),
      .PIPE_DEPTH(SYNC_DEPTH)
  ) ack_sync_inst (
      .clk   (src_clk),
      .rst   (src_rst),
      .data_i(ack_q),
      .data_o(ack_sync)
  );

  assign dst_data_o = hold_q;

endmodule
