module block_sync #(
  parameter int DIN_W      = 64,
  parameter int DOUT_W     = 66,
  parameter int REG_OUTPUT = 0
) (
  input  logic              clk,
  input  logic              rst,
  input  logic [DIN_W-1:0]  data_i,
  input  logic              valid_i,
  output logic [DOUT_W-1:0] data_o,
  output logic              valid_o
);
  localparam int                  SLIP_W   = DOUT_W - DIN_W;
  localparam int                  OFFSET_W = $clog2(DIN_W + 1);
  localparam logic [OFFSET_W-1:0] REFILL   = OFFSET_W'(DIN_W);

  logic [OFFSET_W-1:0] offset_d;
  logic [OFFSET_W-1:0] offset_q;
  logic [DIN_W-1:0]    prev_data_q;
  logic [2*DIN_W-1:0]  window;
  logic                window_valid;

  always_comb begin
    window       = {data_i, prev_data_q};
    window_valid = valid_i && (offset_q != REFILL);
    if (!valid_i) begin
      offset_d = offset_q;
    end else if (offset_q == REFILL) begin
      offset_d = '0;
    end else begin
      offset_d = offset_q + OFFSET_W'(SLIP_W);
    end
  end

  always_ff @(posedge clk) begin
    if (rst) begin
      offset_q    <= REFILL;
      prev_data_q <= 'x;
    end else begin
      offset_q    <= offset_d;
      prev_data_q <= valid_i ? data_i : prev_data_q;
    end
  end

  data_status_pipeline #(
      .DATA_W    (DOUT_W),
      .STATUS_W  (1),
      .PIPE_DEPTH(REG_OUTPUT)
  ) u_data_status_pipeline (
      .clk     (clk),
      .rst     (rst),
      .data_i  (window[offset_q+:DOUT_W]),
      .status_i(window_valid),
      .data_o  (data_o),
      .status_o(valid_o)
  );
endmodule
