module tx_pad_counter
  import pcs_pkg::*;
#(
  parameter int MIN_FRAME_BYTES = 60
) (
  input  logic                  clk,
  input  logic                  rst,
  input  logic                  clear_i,
  input  logic                  step_i,
  input  logic [LAST_BYTES_W:0] word_bytes_i,
  output logic [LAST_BYTES_W:0] end_pos_o,
  output logic                  done_o
);

  localparam int COUNT_W = $clog2(MIN_FRAME_BYTES + PCS_PAYLOAD_BYTES + 1);
  localparam int POS_W   = LAST_BYTES_W + 1;

  logic [COUNT_W-1:0] bytes_d;
  logic [COUNT_W-1:0] bytes_q;

  logic [COUNT_W-1:0] remaining;
  logic [COUNT_W-1:0] bytes_after;
  logic               pad_needed;

  always_comb begin
    remaining  = COUNT_W'(MIN_FRAME_BYTES) - bytes_q;
    pad_needed = bytes_q + COUNT_W'(word_bytes_i) < COUNT_W'(MIN_FRAME_BYTES);

    bytes_after = bytes_q + COUNT_W'(PCS_PAYLOAD_BYTES);
    if (bytes_after > COUNT_W'(MIN_FRAME_BYTES)) begin
      bytes_after = COUNT_W'(MIN_FRAME_BYTES);
    end
  end

  always_comb begin
    bytes_d = bytes_q;
    if (step_i) begin
      bytes_d = bytes_after;
    end
    if (clear_i) begin
      bytes_d = '0;
    end
  end

  always_ff @(posedge clk) begin
    if (rst) begin
      bytes_q <= '0;
    end else begin
      bytes_q <= bytes_d;
    end
  end

  always_comb begin
    done_o    = !pad_needed || remaining <= COUNT_W'(PCS_PAYLOAD_BYTES);
    end_pos_o = word_bytes_i;
    if (pad_needed) begin
      end_pos_o = POS_W'(remaining);
    end
  end

endmodule
