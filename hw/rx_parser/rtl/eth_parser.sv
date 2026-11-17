module eth_parser
  import pcs_pkg::*;
  import parser_pkg::*;
(
  input  logic                                    clk,
  input  logic                                    rst,
  input  rx_eth_stream_t                          eth_stream_i,
  output rx_eth_stream_t                          eth_stream_o,
  output logic           [OFF_W-LAST_BYTES_W-1:0] word_idx_o,
  output logic                                    hdr_done_o,
  output logic           [VLAN_COUNT_W-1:0]       vlan_count_o,
  output logic                                    vlan_overflow_o,
  output logic                                    ip_v4_o,
  output logic                                    ip_v6_o
);

  localparam int WORD_IDX_W = OFF_W - LAST_BYTES_W;

  logic           [WORD_IDX_W-1:0]                           word_idx_d;
  logic           [WORD_IDX_W-1:0]                           word_idx_q;
  logic           [OFF_W-1:0]                                pos;
  logic                                                      lane_valid;
  logic           [BYTE_W-1:0]                               lane_data;

  logic           [ETHERTYPE_POSITIONS-1:0][ETHERTYPE_W-1:0] ethertype_d;
  logic           [ETHERTYPE_POSITIONS-1:0][ETHERTYPE_W-1:0] ethertype_q;
  logic           [ETHERTYPE_POSITIONS-1:0]                  seen_d;
  logic           [ETHERTYPE_POSITIONS-1:0]                  seen_q;

  logic           [ETHERTYPE_POSITIONS-1:0]                  is_vlan;
  logic           [VLAN_COUNT_W-1:0]                         vlan_count;
  logic                                                      vlan_overflow;
  logic                                                      hdr_done;
  logic                                                      ip_v4;
  logic                                                      ip_v6;

  rx_eth_stream_t                                            stream_q;
  logic                                                      stream_valid_q;
  logic           [WORD_IDX_W-1:0]                           stream_idx_q;

  always_comb begin
    word_idx_d  = word_idx_q;
    seen_d      = seen_q;
    ethertype_d = ethertype_q;
    pos         = '0;
    lane_valid  = 1'b0;
    lane_data   = '0;

    if (eth_stream_i.valid && word_idx_q == '0) begin
      seen_d = '0;
    end

    for (int i = 0; i < ETH_DATA_BYTES; i++) begin
      pos        = {word_idx_q, LAST_BYTES_W'(i)};
      lane_valid = eth_stream_i.valid && (!eth_stream_i.last || i < int'(eth_stream_i.last_bytes));
      lane_data  = eth_stream_i.data[i*BYTE_W+:BYTE_W];

      if (lane_valid) begin
        if (pos == ETHERTYPE_POS_0) begin
          ethertype_d[0][ETHERTYPE_W-1-:BYTE_W] = lane_data;
        end
        if (pos == ETHERTYPE_POS_0 + 1'b1) begin
          ethertype_d[0][BYTE_W-1:0] = lane_data;
          seen_d[0]                  = 1'b1;
        end
        if (pos == ETHERTYPE_POS_1) begin
          ethertype_d[1][ETHERTYPE_W-1-:BYTE_W] = lane_data;
        end
        if (pos == ETHERTYPE_POS_1 + 1'b1) begin
          ethertype_d[1][BYTE_W-1:0] = lane_data;
          seen_d[1]                  = 1'b1;
        end
        if (pos == ETHERTYPE_POS_2) begin
          ethertype_d[2][ETHERTYPE_W-1-:BYTE_W] = lane_data;
        end
        if (pos == ETHERTYPE_POS_2 + 1'b1) begin
          ethertype_d[2][BYTE_W-1:0] = lane_data;
          seen_d[2]                  = 1'b1;
        end
      end
    end

    if (eth_stream_i.valid) begin
      if (eth_stream_i.last) begin
        word_idx_d = '0;
      end else if (word_idx_q != '1) begin
        word_idx_d = word_idx_q + 1'b1;
      end
    end
  end

  always_comb begin
    for (int k = 0; k < ETHERTYPE_POSITIONS; k++) begin
      is_vlan[k] = ethertype_q[k] == ETHERTYPE_VLAN || ethertype_q[k] == ETHERTYPE_QINQ;
    end

    vlan_count = VLAN_COUNT_W'(MAX_VLANS);
    for (int k = MAX_VLANS - 1; k >= 0; k--) begin
      if (!is_vlan[k]) begin
        vlan_count = VLAN_COUNT_W'(k);
      end
    end

    vlan_overflow = seen_q[MAX_VLANS] && int'(vlan_count) == MAX_VLANS && is_vlan[MAX_VLANS];
    hdr_done      = seen_q[vlan_count];
    ip_v4         = hdr_done && !vlan_overflow && ethertype_q[vlan_count] == ETHERTYPE_IPV4;
    ip_v6         = hdr_done && !vlan_overflow && ethertype_q[vlan_count] == ETHERTYPE_IPV6;
  end

  always_ff @(posedge clk) begin
    if (rst) begin
      word_idx_q     <= '0;
      seen_q         <= '0;
      stream_valid_q <= 1'b0;
      ethertype_q    <= 'x;
      stream_q       <= 'x;
      stream_idx_q   <= 'x;
    end else begin
      word_idx_q     <= word_idx_d;
      seen_q         <= seen_d;
      stream_valid_q <= eth_stream_i.valid;
      ethertype_q    <= ethertype_d;
      stream_q       <= eth_stream_i;
      stream_idx_q   <= word_idx_q;
    end
  end

  always_comb begin
    eth_stream_o       = stream_q;
    eth_stream_o.valid = stream_valid_q;
    word_idx_o         = stream_idx_q;
    hdr_done_o         = hdr_done;
    vlan_count_o       = vlan_count;
    vlan_overflow_o    = vlan_overflow;
    ip_v4_o            = ip_v4;
    ip_v6_o            = ip_v6;
  end

endmodule
