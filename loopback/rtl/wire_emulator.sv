// Pre-loads OFFSET_BITS of pseudo-random garbage so RX must bitslip
// to find alignment, emulating a real wire mid-stream start.

module wire_emulator #(
    parameter int OFFSET_BITS = 17
) (
    input  logic        clk,
    input  logic        rst,

    input  logic [63:0] tx_data_i,
    input  logic        tx_valid_i,

    output logic [63:0] rx_data_o,
    output logic        rx_valid_o,

    input  logic        slip_i
);

  localparam logic [255:0] GARBAGE_SEED =
      256'h0123_4567_89AB_CDEF_FEDC_BA98_7654_3210_DEAD_BEEF_CAFE_BABE_0F0F_F0F0_AAAA_5555;

  logic [255:0] buffer_d, buffer_q;
  logic [8:0]   count_d, count_q;

  always_comb begin
    buffer_d   = buffer_q;
    count_d    = count_q;
    rx_data_o  = 64'h0;
    rx_valid_o = 1'b0;

    if (slip_i && (count_d != 0)) begin
      buffer_d = buffer_d >> 1;
      count_d  = count_d - 9'd1;
    end

    if (tx_valid_i) begin
      buffer_d = buffer_d | (256'(tx_data_i) << count_d);
      count_d  = count_d + 9'd64;
    end

    if (count_d >= 9'd64) begin
      rx_data_o  = buffer_d[63:0];
      rx_valid_o = 1'b1;
      buffer_d   = buffer_d >> 64;
      count_d    = count_d - 9'd64;
    end
  end

  always_ff @(posedge clk) begin
    if (rst) begin
      buffer_q <= GARBAGE_SEED;
      count_q  <= 9'(OFFSET_BITS);
    end else begin
      buffer_q <= buffer_d;
      count_q  <= count_d;
    end
  end

endmodule
