module csum_insert
  import tx_meta_pkg::*;
  import csum_pkg::*;
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

  logic                                      advance;
  logic                                      accept;
  csum_result_t                              frame_result;
  logic         [TX_OFF_W-1:0]               csum_hi_pos;
  logic         [TX_OFF_W-1:0]               csum_lo_pos;
  logic                                      csum_hi_in_word;
  logic                                      csum_lo_in_word;
  logic         [DATA_BYTES-1:0][BYTE_W-1:0] data_out;

  logic                                      first_d;
  logic                                      first_q;
  csum_result_t                              result_d;
  csum_result_t                              result_q;
  logic         [TX_OFF_W-1:0]               pos_d;
  logic         [TX_OFF_W-1:0]               pos_q;

  logic         [DATA_W-1:0]                 data_d;
  logic         [DATA_W-1:0]                 data_q;
  logic         [LAST_BYTES_W-1:0]           last_bytes_d;
  logic         [LAST_BYTES_W-1:0]           last_bytes_q;
  logic                                      last_d;
  logic                                      last_q;
  logic                                      valid_d;
  logic                                      valid_q;

  always_comb begin
    advance         = !valid_q || m_stream.ready;
    s_stream.ready  = !rst && advance && (!first_q || result_valid_i);
    accept          = s_stream.valid && s_stream.ready;
    result_ready_o  = accept && first_q;

    frame_result    = first_q ? result_i : result_q;
    csum_hi_pos     = frame_result.l4_pos;
    csum_lo_pos     = frame_result.l4_pos + TX_OFF_W'(1);
    csum_hi_in_word = frame_result.l4_en && csum_hi_pos[TX_OFF_W-1:LANE_W] == pos_q[TX_OFF_W-1:LANE_W];
    csum_lo_in_word = frame_result.l4_en && csum_lo_pos[TX_OFF_W-1:LANE_W] == pos_q[TX_OFF_W-1:LANE_W];

    data_out        = {>>{s_stream.data}};
    if (csum_hi_in_word) begin
      data_out[csum_hi_pos[LANE_W-1:0]] = frame_result.l4_csum[CSUM_W-1-:BYTE_W];
    end
    if (csum_lo_in_word) begin
      data_out[csum_lo_pos[LANE_W-1:0]] = frame_result.l4_csum[BYTE_W-1:0];
    end

    first_d         = first_q;
    result_d        = result_q;
    pos_d           = pos_q;
    data_d          = data_q;
    last_bytes_d    = last_bytes_q;
    last_d          = last_q;
    valid_d         = valid_q;

    if (advance) begin
      valid_d = accept;
    end

    if (accept) begin
      first_d      = s_stream.last;
      result_d     = frame_result;
      pos_d        = pos_q + TX_OFF_W'(DATA_BYTES);
      data_d       = {>>{data_out}};
      last_bytes_d = s_stream.last_bytes;
      last_d       = s_stream.last;
      if (s_stream.last) begin
        pos_d = '0;
      end
    end
  end

  always_ff @(posedge clk) begin
    if (rst) begin
      first_q      <= 1'b1;
      pos_q        <= '0;
      valid_q      <= 1'b0;
      result_q     <= 'x;
      data_q       <= 'x;
      last_bytes_q <= 'x;
      last_q       <= 'x;
    end else begin
      first_q      <= first_d;
      pos_q        <= pos_d;
      valid_q      <= valid_d;
      result_q     <= result_d;
      data_q       <= data_d;
      last_bytes_q <= last_bytes_d;
      last_q       <= last_d;
    end
  end

  always_comb begin
    m_stream.data       = data_q;
    m_stream.last_bytes = last_bytes_q;
    m_stream.last       = last_q;
    m_stream.valid      = valid_q;
  end

endmodule
