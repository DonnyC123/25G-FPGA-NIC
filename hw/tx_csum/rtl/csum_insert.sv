module csum_insert
  import parser_pkg::*;
  import pcs_pkg::BYTE_W;
(
  input  logic                   clk,
  input  logic                   rst,
         tx_eth_stream_if.slave  s_stream,
  input  csum_result_t           result_i,
  input  logic                   result_valid_i,
  output logic                   result_ready_o,
         tx_eth_stream_if.master m_stream
);

  localparam int DATA_W       = s_stream.DATA_W;
  localparam int DATA_BYTES   = s_stream.DATA_BYTES;
  localparam int LAST_BYTES_W = s_stream.LAST_BYTES_W;
  localparam int LANE_W       = $clog2(DATA_BYTES);

  function automatic logic [DATA_BYTES-1:0][BYTE_W-1:0] patch(input logic [DATA_BYTES-1:0][BYTE_W-1:0] data,
                                                              input logic [OFF_W-1:0] word_pos,
                                                              input logic en, input logic [OFF_W-1:0] field_pos,
                                                              input logic [CSUM_W-1:0] csum);
    logic [LANE_W-1:0] lane;
    patch = data;
    lane  = field_pos[LANE_W-1:0];
    if (en && field_pos[OFF_W-1:LANE_W] == word_pos[OFF_W-1:LANE_W]) begin
      patch[lane] = csum[CSUM_W-1-:BYTE_W];
      if (lane != '1) begin
        patch[lane+1'b1] = csum[BYTE_W-1:0];
      end
    end
  endfunction

  logic                    have_d;
  logic                    have_q;
  csum_result_t            result_d;
  csum_result_t            result_q;
  logic [OFF_W-1:0]        word_pos_d;
  logic [OFF_W-1:0]        word_pos_q;

  logic [DATA_W-1:0]       data_d;
  logic [DATA_W-1:0]       data_q;
  logic [LAST_BYTES_W-1:0] last_bytes_d;
  logic [LAST_BYTES_W-1:0] last_bytes_q;
  logic                    last_d;
  logic                    last_q;
  logic                    valid_d;
  logic                    valid_q;

  logic                    advance;
  logic                    accept;
  csum_result_t            result;

  always_comb begin
    advance        = !valid_q || m_stream.ready;
    result         = have_q ? result_q : result_i;
    s_stream.ready = !rst && advance && (have_q || result_valid_i);
    accept         = s_stream.valid && s_stream.ready;
    result_ready_o = accept && !have_q;

    have_d         = have_q;
    result_d       = result_q;
    word_pos_d     = word_pos_q;
    data_d         = data_q;
    last_bytes_d   = last_bytes_q;
    last_d         = last_q;
    valid_d        = valid_q;

    if (advance) begin
      valid_d = accept;
    end

    if (accept) begin
      have_d       = !s_stream.last;
      result_d     = result;
      word_pos_d   = s_stream.last ? '0 : word_pos_q + OFF_W'(DATA_BYTES);
      data_d       = patch(patch(s_stream.data, word_pos_q, result.ip_en, result.ip_pos, result.ip_csum), word_pos_q,
                           result.l4_en, result.l4_pos, result.l4_csum);
      last_bytes_d = s_stream.last_bytes;
      last_d       = s_stream.last;
    end
  end

  always_ff @(posedge clk) begin
    if (rst) begin
      have_q     <= 1'b0;
      word_pos_q <= '0;
      valid_q    <= 1'b0;
    end else begin
      have_q     <= have_d;
      word_pos_q <= word_pos_d;
      valid_q    <= valid_d;
    end
  end

  always_ff @(posedge clk) begin
    result_q     <= result_d;
    data_q       <= data_d;
    last_bytes_q <= last_bytes_d;
    last_q       <= last_d;
  end

  always_comb begin
    m_stream.data       = data_q;
    m_stream.last_bytes = last_bytes_q;
    m_stream.last       = last_q;
    m_stream.valid      = valid_q;
  end

endmodule
