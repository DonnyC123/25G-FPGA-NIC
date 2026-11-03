module rx_lock_watchdog #(
  parameter int TIMEOUT_CYCLES = 1_000_000,
  parameter int PULSE_CYCLES   = 1_000
) (
  input  logic clk,
  input  logic rst,
  input  logic rx_reset_done_i,
  input  logic locked_i,
  output logic rx_reset_o
);

  localparam int COUNT_MAX = TIMEOUT_CYCLES > PULSE_CYCLES ? TIMEOUT_CYCLES : PULSE_CYCLES;
  localparam int COUNT_W   = $clog2(COUNT_MAX);
  localparam int SYNC_W    = 2;

  logic [SYNC_W-1:0]  status_sync [2];
  logic               rx_reset_done;
  logic               locked;

  logic [COUNT_W-1:0] count_d;
  logic [COUNT_W-1:0] count_q;
  logic               pulse_d;
  logic               pulse_q;

  shift_reg #(
      .DATA_W    (SYNC_W),
      .PIPE_DEPTH(2)
  ) status_sync_inst (
      .clk   (clk),
      .rst   (rst),
      .data_i({rx_reset_done_i, locked_i}),
      .data_o(status_sync)
  );

  always_comb begin
    {rx_reset_done, locked} = status_sync[1];

    count_d = count_q + 1'b1;
    pulse_d = pulse_q;

    if (pulse_q) begin
      if (count_q == COUNT_W'(PULSE_CYCLES - 1)) begin
        count_d = '0;
        pulse_d = 1'b0;
      end
    end else if (locked || !rx_reset_done) begin
      count_d = '0;
    end else if (count_q == COUNT_W'(TIMEOUT_CYCLES - 1)) begin
      count_d = '0;
      pulse_d = 1'b1;
    end
  end

  always_ff @(posedge clk) begin
    if (rst) begin
      count_q <= '0;
      pulse_q <= 1'b0;
    end else begin
      count_q <= count_d;
      pulse_q <= pulse_d;
    end
  end

  assign rx_reset_o = pulse_q;

endmodule
