module ipv6_parser
  import pcs_pkg::*;
  import parser_pkg::*;
(
  input  logic                                      clk,
  input  logic                                      rst,
  input  rx_eth_stream_t                            eth_stream_i,
  input  logic           [OFF_W-LAST_BYTES_W-1:0]   word_idx_i,
  input  logic           [VLAN_COUNT_W-1:0]         vlan_count_i,
  input  logic                                      ip_v6_i,
  output rx_eth_stream_t                            eth_stream_o,
  output logic           [OFF_W-LAST_BYTES_W-1:0]   word_idx_o,
  output logic                                      hdr_done_o,
  output logic           [IPV6_ADDR_LEN*BYTE_W-1:0] src_addr_o,
  output logic           [IPV6_ADDR_LEN*BYTE_W-1:0] dst_addr_o,
  output logic           [IP_PROTO_W-1:0]           proto_o,
  output logic           [OFF_W-1:0]                l4_pos_o
);

  localparam int WORD_IDX_W = OFF_W - LAST_BYTES_W;
  localparam int DST_OFF    = IPV6_ADDR_OFF + IPV6_ADDR_LEN;

  localparam logic [OFF_W-1:0] L4_REL = OFF_W'(IPV6_HDR_BYTES);

  logic [OFF_W-1:0]                     pos;
  logic                                 lane_valid;
  logic [BYTE_W-1:0]                    lane_data;

  logic [IPV6_ADDR_LEN-1:0][BYTE_W-1:0] src_addr_d;
  logic [IPV6_ADDR_LEN-1:0][BYTE_W-1:0] src_addr_q;
  logic [IPV6_ADDR_LEN-1:0][BYTE_W-1:0] dst_addr_d;
  logic [IPV6_ADDR_LEN-1:0][BYTE_W-1:0] dst_addr_q;
  logic [IP_PROTO_W-1:0]                proto_d;
  logic [IP_PROTO_W-1:0]                proto_q;
  logic [OFF_W-1:0]                     l4_pos_d;
  logic [OFF_W-1:0]                     l4_pos_q;
  logic                                 seen_d;
  logic                                 seen_q;
  logic                                 ip_v6_q;

  rx_eth_stream_t                       stream_q;
  logic                                 stream_valid_q;
  logic [WORD_IDX_W-1:0]                stream_idx_q;

  always_comb begin
    src_addr_d = src_addr_q;
    dst_addr_d = dst_addr_q;
    proto_d    = proto_q;
    l4_pos_d   = l4_pos_q;
    seen_d     = seen_q;
    pos        = '0;
    lane_valid = 1'b0;
    lane_data  = '0;

    if (eth_stream_i.valid && word_idx_i == '0) begin
      seen_d = 1'b0;
    end

    for (int i = 0; i < ETH_DATA_BYTES; i++) begin
      pos        = {word_idx_i, LAST_BYTES_W'(i)};
      lane_valid = eth_stream_i.valid && (!eth_stream_i.last || i < int'(eth_stream_i.last_bytes));
      lane_data  = eth_stream_i.data[i*BYTE_W+:BYTE_W];

      if (lane_valid) begin
        if (ip_at(pos, vlan_count_i, OFF_W'(IPV6_NH_OFF))) begin
          proto_d  = lane_data;
          l4_pos_d = ip_pos(vlan_count_i) + L4_REL;
        end
        for (int b = 0; b < IPV6_ADDR_LEN; b++) begin
          if (ip_at(pos, vlan_count_i, OFF_W'(IPV6_ADDR_OFF + b))) begin
            src_addr_d[IPV6_ADDR_LEN-1-b] = lane_data;
          end
          if (ip_at(pos, vlan_count_i, OFF_W'(DST_OFF + b))) begin
            dst_addr_d[IPV6_ADDR_LEN-1-b] = lane_data;
          end
        end
        if (ip_at(pos, vlan_count_i, OFF_W'(DST_OFF + IPV6_ADDR_LEN - 1))) begin
          seen_d = 1'b1;
        end
      end
    end
  end

  always_ff @(posedge clk) begin
    if (rst) begin
      seen_q         <= 1'b0;
      ip_v6_q        <= 1'b0;
      stream_valid_q <= 1'b0;
    end else begin
      seen_q         <= seen_d;
      ip_v6_q        <= ip_v6_i;
      stream_valid_q <= eth_stream_i.valid;
    end
  end

  always_ff @(posedge clk) begin
    src_addr_q   <= src_addr_d;
    dst_addr_q   <= dst_addr_d;
    proto_q      <= proto_d;
    l4_pos_q     <= l4_pos_d;
    stream_q     <= eth_stream_i;
    stream_idx_q <= word_idx_i;
  end

  always_comb begin
    eth_stream_o       = stream_q;
    eth_stream_o.valid = stream_valid_q;
  end

  assign word_idx_o = stream_idx_q;
  assign hdr_done_o = ip_v6_q && seen_q;
  assign src_addr_o = src_addr_q;
  assign dst_addr_o = dst_addr_q;
  assign proto_o    = proto_q;
  assign l4_pos_o   = l4_pos_q;

endmodule
