module skid_buffer #(
  parameter int DATA_W = 64
) (
  input  logic              clk,
  input  logic              rst,

  input  logic [DATA_W-1:0] data_i,
  input  logic              valid_i,
  output logic              ready_o,

  output logic [DATA_W-1:0] data_o,
  output logic              valid_o,
  input  logic              ready_i
);

  logic [DATA_W-1:0] out_data_d;
  logic [DATA_W-1:0] out_data_q;
  logic              out_valid_d;
  logic              out_valid_q;

  logic [DATA_W-1:0] skid_data_d;
  logic [DATA_W-1:0] skid_data_q;
  logic              skid_valid_d;
  logic              skid_valid_q;

  always_comb begin
    ready_o      = !skid_valid_q;

    out_data_d   = out_data_q;
    out_valid_d  = out_valid_q;
    skid_data_d  = skid_data_q;
    skid_valid_d = skid_valid_q;

    if (!out_valid_q || ready_i) begin
      out_data_d  = data_i;
      out_valid_d = valid_i;
      if (skid_valid_q) begin
        out_data_d   = skid_data_q;
        out_valid_d  = 1'b1;
        skid_valid_d = 1'b0;
      end
    end else if (valid_i && ready_o) begin
      skid_data_d  = data_i;
      skid_valid_d = 1'b1;
    end
  end

  always_ff @(posedge clk) begin
    if (rst) begin
      out_valid_q  <= 1'b0;
      skid_valid_q <= 1'b0;
    end else begin
      out_valid_q  <= out_valid_d;
      skid_valid_q <= skid_valid_d;
    end
  end

  always_ff @(posedge clk) begin
    out_data_q  <= out_data_d;
    skid_data_q <= skid_data_d;
  end

  always_comb begin
    data_o  = out_data_q;
    valid_o = out_valid_q;
  end

endmodule
