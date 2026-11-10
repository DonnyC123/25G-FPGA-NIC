module parse_reg
  import parser_pkg::*;
(
  input  logic                clk,
  input  logic                rst,
         axi_stream_if.slave  s_axi,
  input  parse_meta_t         meta_i,
  output logic                accept_o,
         axi_stream_if.master m_axi,
  output parse_meta_t         meta_o
);

  localparam int DATA_W = s_axi.DATA_W;
  localparam int MASK_W = s_axi.MASK_W;

  logic [DATA_W-1:0] data_d;
  logic [DATA_W-1:0] data_q;
  logic [MASK_W-1:0] mask_d;
  logic [MASK_W-1:0] mask_q;
  logic              last_d;
  logic              last_q;
  logic              valid_d;
  logic              valid_q;
  parse_meta_t       meta_d;
  parse_meta_t       meta_q;

  logic              advance;

  always_comb begin
    advance     = !valid_q || m_axi.ready;
    s_axi.ready = !rst && advance;
    accept_o    = s_axi.valid && s_axi.ready;

    data_d      = data_q;
    mask_d      = mask_q;
    last_d      = last_q;
    valid_d     = valid_q;
    meta_d      = meta_q;

    if (advance) begin
      valid_d = accept_o;
    end

    if (accept_o) begin
      data_d = s_axi.data;
      mask_d = s_axi.mask;
      last_d = s_axi.last;
      meta_d = meta_i;
    end
  end

  always_ff @(posedge clk) begin
    if (rst) begin
      valid_q <= 1'b0;
    end else begin
      valid_q <= valid_d;
    end
  end

  always_ff @(posedge clk) begin
    data_q <= data_d;
    mask_q <= mask_d;
    last_q <= last_d;
    meta_q <= meta_d;
  end

  always_comb begin
    m_axi.data  = data_q;
    m_axi.mask  = mask_q;
    m_axi.last  = last_q;
    m_axi.valid = valid_q;
    meta_o      = meta_q;
  end

endmodule
