module tx_gearbox #(
  parameter int DIN_W      = 66,
  parameter int DOUT_W     = 64,
  parameter int REG_OUTPUT = 0
) (
  input  logic              clk,
  input  logic              rst,
  input  logic [DIN_W-1:0]  data_i,
  input  logic              valid_i,
  output logic              ready_o,
  output logic [DOUT_W-1:0] data_o,
  output logic              valid_o
);
  localparam int                  SLIP_W   = DIN_W - DOUT_W;
  localparam int                  OFFSET_W = $clog2(2 * DIN_W);
  localparam logic [OFFSET_W-1:0] EMPTY    = OFFSET_W'(DIN_W);
  localparam logic [OFFSET_W-1:0] DRAIN    = OFFSET_W'(SLIP_W);

  logic [OFFSET_W-1:0] offset_d;
  logic [OFFSET_W-1:0] offset_q;
  logic [DIN_W-1:0]    prev_data_d;
  logic [DIN_W-1:0]    prev_data_q;
  logic [2*DIN_W-1:0]  window;
  logic                window_valid;
  logic                drain;

  always_comb begin
    window       = {data_i, prev_data_q};
    drain        = offset_q == DRAIN;
    window_valid = valid_i || drain;

    offset_d    = offset_q;
    prev_data_d = prev_data_q;
    if (valid_i) begin
      offset_d    = offset_q - OFFSET_W'(SLIP_W);
      prev_data_d = data_i;
    end
    if (drain) begin
      offset_d = EMPTY;
    end

    ready_o = offset_d != DRAIN;
  end

  always_ff @(posedge clk) begin
    if (rst) begin
      offset_q <= EMPTY;
    end else begin
      offset_q <= offset_d;
    end
  end

  always_ff @(posedge clk) begin
    prev_data_q <= prev_data_d;
  end

  data_status_pipeline #(
      .DATA_W    (DOUT_W),
      .STATUS_W  (1),
      .PIPE_DEPTH(REG_OUTPUT)
  ) data_status_pipeline_inst (
      .clk     (clk),
      .rst     (rst),
      .data_i  (window[offset_q+:DOUT_W]),
      .status_i(window_valid),
      .data_o  (data_o),
      .status_o(valid_o)
  );
endmodule
