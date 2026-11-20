module ipv6_ext_walk
  import pcs_pkg::*;
  import parser_pkg::*;
(
  input  logic                            clk,
  input  logic                            rst,
  input  rx_eth_stream_t                  eth_stream_i,
  input  rx_word_idx_t                    word_idx_i,
  input  logic                            ip_v6_i,
  input  logic           [IP_PROTO_W-1:0] proto_i,
  input  rx_off_t                         l4_pos_i,
  output rx_eth_stream_t                  eth_stream_o,
  output rx_word_idx_t                    word_idx_o,
  output logic                            hdr_done_o,
  output logic           [IP_PROTO_W-1:0] proto_o,
  output logic                            frag_o,
  output rx_off_t                         l4_pos_o
);

  localparam int               GAP_W    = IPV6_EXT_LEN_W + 1;
  localparam int               AH_SUM_W = IPV6_EXT_LEN_W + IPV6_AH_SHIFT + 1;

  localparam logic [GAP_W-1:0] GAP_ONE  = 1;

  function automatic logic skippable(input logic [IP_PROTO_W-1:0] proto);
    return proto == IP_PROTO_HOPOPT || proto == IP_PROTO_ROUTING || proto == IP_PROTO_DSTOPTS || proto == IP_PROTO_AH;
  endfunction

  logic         [ETH_DATA_BYTES:0]  [BYTE_W-1:0]       lanes;
  logic         [LAST_BYTES_W-1:0]                     lane_idx;
  logic         [IPV6_EXT_LEN_W-1:0]                   lane_len;

  logic         [ETH_DATA_BYTES-1:0][IP_PROTO_W-1:0]   nh_by_lane;
  logic         [ETH_DATA_BYTES-1:0][GAP_W-1:0]        opt_gap_by_lane;
  logic         [ETH_DATA_BYTES-1:0][GAP_W-1:0]        ah_gap_by_lane;
  logic         [ETH_DATA_BYTES-1:0]                   opt_gap_zero_by_lane;
  logic         [ETH_DATA_BYTES-1:0]                   ah_gap_zero_by_lane;
  logic         [ETH_DATA_BYTES-1:0][LAST_BYTES_W-1:0] ah_lane_by_lane;

  logic                                                is_ah;
  logic                                                at_header;
  logic                                                len_present;
  logic                                                hit;
  logic         [GAP_W-1:0]                            gap;
  logic                                                gap_zero;

  logic         [IP_PROTO_W-1:0]                       proto_d;
  logic         [IP_PROTO_W-1:0]                       proto_q;
  logic         [LAST_BYTES_W-1:0]                     lane_d;
  logic         [LAST_BYTES_W-1:0]                     lane_q;
  rx_word_idx_t                                        cur_word_d;
  rx_word_idx_t                                        cur_word_q;
  logic         [GAP_W-1:0]                            words_left_d;
  logic         [GAP_W-1:0]                            words_left_q;
  logic                                                at_header_d;
  logic                                                at_header_q;
  logic                                                walk_started_d;
  logic                                                walk_started_q;
  logic                                                advance_q;
  logic         [GAP_W-1:0]                            advance_gap_q;

  logic         [IP_PROTO_W-1:0]                       out_proto_q;
  logic         [LAST_BYTES_W-1:0]                     out_lane_q;
  logic                                                out_ip_v6;

  always_comb begin
    lanes    = {{BYTE_W{1'b0}}, eth_stream_i.data};
    lane_idx = '0;
    lane_len = '0;

    for (int i = 0; i < ETH_DATA_BYTES; i++) begin
      lane_idx                = i[LAST_BYTES_W-1:0];
      lane_len                = lanes[i+IPV6_EXT_LEN_OFF];
      nh_by_lane[i]           = lanes[i+IPV6_EXT_NH_OFF];
      opt_gap_by_lane[i]      = GAP_W'(lane_len);
      ah_gap_by_lane[i]       = GAP_W'(((AH_SUM_W'(lane_len) << IPV6_AH_SHIFT) + AH_SUM_W'(lane_idx)) >> LAST_BYTES_W);
      opt_gap_zero_by_lane[i] = opt_gap_by_lane[i] == '0;
      ah_gap_zero_by_lane[i]  = ah_gap_by_lane[i] == '0;
      ah_lane_by_lane[i]      = lane_idx + LAST_BYTES_W'(lane_len << IPV6_AH_SHIFT);
    end
  end

  always_comb begin
    is_ah       = proto_q == IP_PROTO_AH;
    at_header   = walk_started_q ? at_header_q : word_idx_i == cur_word_q;
    len_present = !eth_stream_i.last || int'(lane_q) + IPV6_EXT_LEN_OFF < int'(eth_stream_i.last_bytes);
    hit         = eth_stream_i.valid && at_header && len_present && ip_v6_i && skippable(proto_q);
    gap         = is_ah ? ah_gap_by_lane[lane_q] : opt_gap_by_lane[lane_q];
    gap_zero    = is_ah ? ah_gap_zero_by_lane[lane_q] : opt_gap_zero_by_lane[lane_q];
  end

  always_comb begin
    proto_d        = proto_q;
    lane_d         = lane_q;
    cur_word_d     = cur_word_q;
    words_left_d   = words_left_q;
    at_header_d    = at_header_q;
    walk_started_d = walk_started_q;

    if (advance_q) begin
      cur_word_d = cur_word_q + RX_WORD_IDX_W'(advance_gap_q) + 1'b1;
    end

    if (!walk_started_q) begin
      proto_d    = proto_i;
      lane_d     = l4_pos_i[LAST_BYTES_W-1:0];
      cur_word_d = l4_pos_i[RX_OFF_W-1:LAST_BYTES_W];
    end

    if (eth_stream_i.valid && walk_started_q) begin
      words_left_d = words_left_q - 1'b1;
      at_header_d  = words_left_q == GAP_ONE;
    end

    if (hit) begin
      proto_d        = nh_by_lane[lane_q];
      lane_d         = is_ah ? ah_lane_by_lane[lane_q] : lane_q;
      words_left_d   = gap;
      at_header_d    = gap_zero;
      walk_started_d = 1'b1;
    end

    if (eth_stream_i.valid && word_idx_i == '0) begin
      walk_started_d = 1'b0;
    end
  end

  always_ff @(posedge clk) begin
    if (rst) begin
      walk_started_q <= 1'b0;
      at_header_q    <= 1'b0;
      advance_q      <= 1'b0;
    end else begin
      walk_started_q <= walk_started_d;
      at_header_q    <= at_header_d;
      advance_q      <= hit;
    end
  end

  always_ff @(posedge clk) begin
    proto_q       <= proto_d;
    lane_q        <= lane_d;
    cur_word_q    <= cur_word_d;
    words_left_q  <= words_left_d;
    advance_gap_q <= gap;
    out_proto_q   <= proto_q;
    out_lane_q    <= lane_q;
  end

  data_status_pipeline #(
      .DATA_W    ($bits(eth_stream_i.data) + $bits(eth_stream_i.last_bytes) + $bits(eth_stream_i.last) + RX_WORD_IDX_W),
      .STATUS_W  ($bits(eth_stream_i.valid) + $bits(eth_stream_i.drop) + $bits(ip_v6_i)),
      .PIPE_DEPTH(IPV6_EXT_WALK_LATENCY)
  ) stream_pipeline_inst (
      .clk     (clk),
      .rst     (rst),
      .data_i  ({eth_stream_i.data, eth_stream_i.last_bytes, eth_stream_i.last, word_idx_i}),
      .status_i({eth_stream_i.valid, eth_stream_i.drop, ip_v6_i}),
      .data_o  ({eth_stream_o.data, eth_stream_o.last_bytes, eth_stream_o.last, word_idx_o}),
      .status_o({eth_stream_o.valid, eth_stream_o.drop, out_ip_v6})
  );

  assign hdr_done_o = out_ip_v6 && !skippable(out_proto_q);
  assign proto_o    = out_proto_q;
  assign frag_o     = out_ip_v6 && out_proto_q == IP_PROTO_FRAGMENT;
  assign l4_pos_o   = {cur_word_q, out_lane_q};

endmodule
