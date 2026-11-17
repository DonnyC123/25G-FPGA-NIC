module ipv6_ext_walk
  import pcs_pkg::*;
  import parser_pkg::*;
(
  input  logic                                    clk,
  input  logic                                    rst,
  input  rx_eth_stream_t                          eth_stream_i,
  input  logic           [OFF_W-LAST_BYTES_W-1:0] word_idx_i,
  input  logic                                    ip_v6_i,
  input  logic           [IP_PROTO_W-1:0]         proto_i,
  input  logic           [OFF_W-1:0]              l4_pos_i,
  output rx_eth_stream_t                          eth_stream_o,
  output logic           [OFF_W-LAST_BYTES_W-1:0] word_idx_o,
  output logic                                    hdr_done_o,
  output logic           [IP_PROTO_W-1:0]         proto_o,
  output logic                                    frag_o,
  output logic           [OFF_W-1:0]              l4_pos_o
);

  localparam int WORD_IDX_W = OFF_W - LAST_BYTES_W;

  localparam logic [OFF_W-1:0] NH_REL  = OFF_W'(IPV6_EXT_NH_OFF);
  localparam logic [OFF_W-1:0] LEN_REL = OFF_W'(IPV6_EXT_LEN_OFF);

  logic [OFF_W-1:0]          pos;
  logic                      lane_valid;
  logic [BYTE_W-1:0]         lane_data;

  logic                      skip;
  logic [IP_PROTO_W-1:0]     ext_nh;
  logic [IPV6_EXT_LEN_W-1:0] ext_len;
  logic                      len_seen;

  logic [IP_PROTO_W-1:0]     proto_d;
  logic [IP_PROTO_W-1:0]     proto_q;
  logic [OFF_W-1:0]          cur_pos_d;
  logic [OFF_W-1:0]          cur_pos_q;
  logic                      walk_started_d;
  logic                      walk_started_q;
  logic                      ip_v6_q;

  rx_eth_stream_t            stream_q;
  logic                      stream_valid_q;
  logic [WORD_IDX_W-1:0]     stream_idx_q;

  always_comb begin
    skip = proto_q == IP_PROTO_HOPOPT || proto_q == IP_PROTO_ROUTING || proto_q == IP_PROTO_DSTOPTS ||
           proto_q == IP_PROTO_AH;
  end

  always_comb begin
    proto_d        = proto_q;
    cur_pos_d      = cur_pos_q;
    walk_started_d = walk_started_q;
    pos            = '0;
    lane_valid     = 1'b0;
    lane_data      = '0;
    ext_nh         = '0;
    ext_len        = '0;
    len_seen       = 1'b0;

    for (int i = 0; i < ETH_DATA_BYTES; i++) begin
      pos        = {word_idx_i, LAST_BYTES_W'(i)};
      lane_valid = eth_stream_i.valid && (!eth_stream_i.last || i < int'(eth_stream_i.last_bytes));
      lane_data  = eth_stream_i.data[i*BYTE_W+:BYTE_W];

      if (lane_valid) begin
        if (skip && pos == cur_pos_q + NH_REL) begin
          ext_nh = lane_data;
        end
        if (skip && pos == cur_pos_q + LEN_REL) begin
          ext_len  = lane_data;
          len_seen = 1'b1;
        end
      end
    end

    if (!walk_started_q) begin
      proto_d   = proto_i;
      cur_pos_d = l4_pos_i;
    end

    if (ip_v6_i && len_seen) begin
      proto_d        = ext_nh;
      walk_started_d = 1'b1;
      if (proto_q == IP_PROTO_AH) begin
        cur_pos_d = cur_pos_q + ((OFF_W'(ext_len) + OFF_W'(2'd2)) << IPV6_AH_SHIFT);
      end else begin
        cur_pos_d = cur_pos_q + ((OFF_W'(ext_len) + OFF_W'(1'b1)) << IPV6_EXT_SHIFT);
      end
    end

    if (eth_stream_i.valid && word_idx_i == '0) begin
      walk_started_d = 1'b0;
    end
  end

  always_ff @(posedge clk) begin
    if (rst) begin
      walk_started_q <= 1'b0;
      ip_v6_q        <= 1'b0;
      stream_valid_q <= 1'b0;
    end else begin
      walk_started_q <= walk_started_d;
      ip_v6_q        <= ip_v6_i;
      stream_valid_q <= eth_stream_i.valid;
    end
  end

  always_ff @(posedge clk) begin
    proto_q      <= proto_d;
    cur_pos_q    <= cur_pos_d;
    stream_q     <= eth_stream_i;
    stream_idx_q <= word_idx_i;
  end

  always_comb begin
    eth_stream_o       = stream_q;
    eth_stream_o.valid = stream_valid_q;
  end

  assign word_idx_o = stream_idx_q;
  assign hdr_done_o = ip_v6_q && !skip;
  assign proto_o    = proto_q;
  assign frag_o     = ip_v6_q && proto_q == IP_PROTO_FRAGMENT;
  assign l4_pos_o   = cur_pos_q;

endmodule
