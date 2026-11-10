module field_capture
  import parser_pkg::OFF_W;
  import pcs_pkg::BYTE_W;
#(
  parameter  int BYTES  = 2,
  parameter  int MASK_W = 32,
  localparam int LANE_W = $clog2(MASK_W)
) (
  input  logic                          clk,
  input  logic                          rst,
  input  logic [MASK_W-1:0][BYTE_W-1:0] data_i,
  input  logic [MASK_W-1:0]             mask_i,
  input  logic                          accept_i,
  input  logic                          last_i,
  input  logic                          en_i,
  input  logic [OFF_W-1:0]              pos_i,
  input  logic [OFF_W-1:0]              off_i,

  output logic [BYTES-1:0][BYTE_W-1:0]  field_o,
  output logic                          present_o
);

  logic [BYTES-1:0][BYTE_W-1:0] bytes_q;
  logic [BYTES-1:0]             have_d;
  logic [BYTES-1:0]             have_q;

  logic [BYTES-1:0][OFF_W-1:0]  rel;
  logic [BYTES-1:0]             hit;

  always_comb begin
    for (int k = 0; k < BYTES; k++) begin
      rel[k]             = off_i + OFF_W'(k) - pos_i;
      hit[k]             = en_i && rel[k] < OFF_W'(MASK_W) && mask_i[rel[k][LANE_W-1:0]];
      field_o[BYTES-1-k] = hit[k] ? data_i[rel[k][LANE_W-1:0]] : bytes_q[BYTES-1-k];
    end

    have_d    = have_q | hit;
    present_o = &have_d;
  end

  always_ff @(posedge clk) begin
    if (rst) begin
      have_q <= '0;
    end else if (accept_i) begin
      have_q <= last_i ? '0 : have_d;
    end
  end

  always_ff @(posedge clk) begin
    if (accept_i) begin
      bytes_q <= field_o;
    end
  end

endmodule
