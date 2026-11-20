module ipv4_parser
  import pcs_pkg::*;
  import parser_pkg::*;
(
  input  logic                                      clk,
  input  logic                                      rst,
  input  rx_eth_stream_t                            eth_stream_i,
  input  rx_word_idx_t                              word_idx_i,
  input  logic           [VLAN_COUNT_W-1:0]         vlan_count_i,
  input  logic                                      ip_v4_i,
  output logic                                      hdr_done_o,
  output logic           [IPV4_ADDR_LEN*BYTE_W-1:0] src_addr_o,
  output logic           [IPV4_ADDR_LEN*BYTE_W-1:0] dst_addr_o,
  output logic           [IP_PROTO_W-1:0]           proto_o,
  output logic                                      frag_o,
  output rx_off_t                                   l4_pos_o
);

  localparam int DST_OFF = IPV4_ADDR_OFF + IPV4_ADDR_LEN;

  rx_off_t                                 pos;
  logic                                    lane_valid;
  logic    [BYTE_W-1:0]                    lane_data;

  logic    [IPV4_ADDR_LEN-1:0][BYTE_W-1:0] src_addr_d;
  logic    [IPV4_ADDR_LEN-1:0][BYTE_W-1:0] src_addr_q;
  logic    [IPV4_ADDR_LEN-1:0][BYTE_W-1:0] dst_addr_d;
  logic    [IPV4_ADDR_LEN-1:0][BYTE_W-1:0] dst_addr_q;
  logic    [IP_PROTO_W-1:0]                proto_d;
  logic    [IP_PROTO_W-1:0]                proto_q;
  logic    [IP_LEN_W-1:0]                  frag_d;
  logic    [IP_LEN_W-1:0]                  frag_q;
  rx_off_t                                 l4_pos_d;
  rx_off_t                                 l4_pos_q;
  logic                                    seen_d;
  logic                                    seen_q;
  logic                                    hdr_ok_d;
  logic                                    hdr_ok_q;
  logic                                    ip_v4_q;

  always_comb begin
    src_addr_d = src_addr_q;
    dst_addr_d = dst_addr_q;
    proto_d    = proto_q;
    frag_d     = frag_q;
    l4_pos_d   = l4_pos_q;
    seen_d     = seen_q;
    hdr_ok_d   = hdr_ok_q;
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
        if (ip_at(pos, vlan_count_i, RX_OFF_W'(IPV4_VER_IHL_OFF))) begin
          l4_pos_d = ip_pos(vlan_count_i) + (RX_OFF_W'(lane_data[IPV4_IHL_W-1:0]) << IPV4_IHL_SHIFT);
          hdr_ok_d = lane_data[BYTE_W-1-:IP_VERSION_W] == IP_VERSION_W'(IPV4_VERSION) &&
                     lane_data[IPV4_IHL_W-1:0] >= IPV4_IHL_W'(IPV4_MIN_IHL);
        end
        if (ip_at(pos, vlan_count_i, RX_OFF_W'(IPV4_FRAG_OFF))) begin
          frag_d[IP_LEN_W-1-:BYTE_W] = lane_data;
        end
        if (ip_at(pos, vlan_count_i, RX_OFF_W'(IPV4_FRAG_OFF + 1))) begin
          frag_d[BYTE_W-1:0] = lane_data;
        end
        if (ip_at(pos, vlan_count_i, RX_OFF_W'(IPV4_PROTO_OFF))) begin
          proto_d = lane_data;
        end
        for (int b = 0; b < IPV4_ADDR_LEN; b++) begin
          if (ip_at(pos, vlan_count_i, RX_OFF_W'(IPV4_ADDR_OFF + b))) begin
            src_addr_d[IPV4_ADDR_LEN-1-b] = lane_data;
          end
          if (ip_at(pos, vlan_count_i, RX_OFF_W'(DST_OFF + b))) begin
            dst_addr_d[IPV4_ADDR_LEN-1-b] = lane_data;
          end
        end
        if (ip_at(pos, vlan_count_i, RX_OFF_W'(DST_OFF + IPV4_ADDR_LEN - 1))) begin
          seen_d = 1'b1;
        end
      end
    end
  end

  always_ff @(posedge clk) begin
    if (rst) begin
      seen_q  <= 1'b0;
      ip_v4_q <= 1'b0;
    end else begin
      seen_q  <= seen_d;
      ip_v4_q <= ip_v4_i;
    end
  end

  always_ff @(posedge clk) begin
    src_addr_q <= src_addr_d;
    dst_addr_q <= dst_addr_d;
    proto_q    <= proto_d;
    frag_q     <= frag_d;
    l4_pos_q   <= l4_pos_d;
    hdr_ok_q   <= hdr_ok_d;
  end

  assign hdr_done_o = ip_v4_q && seen_q && hdr_ok_q;
  assign src_addr_o = src_addr_q;
  assign dst_addr_o = dst_addr_q;
  assign proto_o    = proto_q;
  assign frag_o     = (frag_q & IPV4_FRAG_MASK) != '0;
  assign l4_pos_o   = l4_pos_q;

endmodule
