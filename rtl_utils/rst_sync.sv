module rst_sync #(
  parameter int STAGES = 4
) (
  input  logic clk,
  input  logic rst_i,
  output logic rst_o
);

  (* ASYNC_REG = "TRUE" *) logic [STAGES-1:0] sync_q;

  always_ff @(posedge clk or posedge rst_i) begin
    if (rst_i) begin
      sync_q <= '1;
    end else begin
      sync_q <= {sync_q[STAGES-2:0], 1'b0};
    end
  end

  assign rst_o = sync_q[STAGES-1];

endmodule
