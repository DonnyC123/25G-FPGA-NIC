module rx_parser
  import pcs_pkg::*;
  import parser_pkg::*;
(
  input  logic           clk,
  input  logic           rst,
  input  rx_eth_stream_t eth_stream_i,
  output rx_eth_stream_t eth_stream_o,
  output logic           meta_valid_o,
  output rx_parse_meta_t meta_o
);

  localparam int WORD_IDX_W = OFF_W - LAST_BYTES_W;
  localparam int ADDR_W     = IPV6_ADDR_LEN * BYTE_W;

  rx_eth_stream_t                eth_stream;
  logic [WORD_IDX_W-1:0]         eth_word_idx;
  logic [VLAN_COUNT_W-1:0]       eth_vlan_count;
  logic                          eth_ip_v4;
  logic                          eth_ip_v6;

  logic                          v4_done;
  logic [IPV4_ADDR_LEN*BYTE_W-1:0] v4_src_addr;
  logic [IPV4_ADDR_LEN*BYTE_W-1:0] v4_dst_addr;
  logic [IP_PROTO_W-1:0]         v4_proto;
  logic                          v4_frag;
  logic [OFF_W-1:0]              v4_l4_pos;

  rx_eth_stream_t                v6_stream;
  logic [WORD_IDX_W-1:0]         v6_word_idx;
  logic                          v6_done;
  logic [ADDR_W-1:0]             v6_src_addr;
  logic [ADDR_W-1:0]             v6_dst_addr;
  logic [IP_PROTO_W-1:0]         v6_proto;
  logic [OFF_W-1:0]              v6_l4_pos;

  rx_eth_stream_t                walk_stream;
  logic [WORD_IDX_W-1:0]         walk_word_idx;
  logic                          walk_done;
  logic [IP_PROTO_W-1:0]         walk_proto;
  logic                          walk_frag;
  logic [OFF_W-1:0]              walk_l4_pos;

  logic                          v4_done_q;
  logic [IP_PROTO_W-1:0]         v4_proto_q;
  logic                          v4_frag_q;
  logic [OFF_W-1:0]              v4_l4_pos_q;

  logic                          l4_hdr_done;
  logic [IP_PROTO_W-1:0]         l4_proto;
  logic                          l4_frag;
  logic [OFF_W-1:0]              l4_pos;

  rx_eth_stream_t                l4_stream;
  logic                          ports_done;
  logic [PORT_W-1:0]             src_port;
  logic [PORT_W-1:0]             dst_port;
  logic [IP_PROTO_W-1:0]         ports_proto;

  rx_parse_meta_t                meta_d;
  rx_parse_meta_t                meta_q;
  logic                          meta_valid_d;
  logic                          meta_valid_q;

  rx_eth_stream_t                stream_q;
  logic                          stream_valid_q;

  eth_parser eth_parser_inst (
      .clk            (clk),
      .rst            (rst),
      .eth_stream_i   (eth_stream_i),
      .eth_stream_o   (eth_stream),
      .word_idx_o     (eth_word_idx),
      .hdr_done_o     (),
      .vlan_count_o   (eth_vlan_count),
      .vlan_overflow_o(),
      .ip_v4_o        (eth_ip_v4),
      .ip_v6_o        (eth_ip_v6)
  );

  ipv4_parser ipv4_parser_inst (
      .clk         (clk),
      .rst         (rst),
      .eth_stream_i(eth_stream),
      .word_idx_i  (eth_word_idx),
      .vlan_count_i(eth_vlan_count),
      .ip_v4_i     (eth_ip_v4),
      .eth_stream_o(),
      .word_idx_o  (),
      .hdr_done_o  (v4_done),
      .src_addr_o  (v4_src_addr),
      .dst_addr_o  (v4_dst_addr),
      .proto_o     (v4_proto),
      .frag_o      (v4_frag),
      .l4_pos_o    (v4_l4_pos)
  );

  ipv6_parser ipv6_parser_inst (
      .clk         (clk),
      .rst         (rst),
      .eth_stream_i(eth_stream),
      .word_idx_i  (eth_word_idx),
      .vlan_count_i(eth_vlan_count),
      .ip_v6_i     (eth_ip_v6),
      .eth_stream_o(v6_stream),
      .word_idx_o  (v6_word_idx),
      .hdr_done_o  (v6_done),
      .src_addr_o  (v6_src_addr),
      .dst_addr_o  (v6_dst_addr),
      .proto_o     (v6_proto),
      .l4_pos_o    (v6_l4_pos)
  );

  ipv6_ext_walk ipv6_ext_walk_inst (
      .clk         (clk),
      .rst         (rst),
      .eth_stream_i(v6_stream),
      .word_idx_i  (v6_word_idx),
      .ip_v6_i     (v6_done),
      .proto_i     (v6_proto),
      .l4_pos_i    (v6_l4_pos),
      .eth_stream_o(walk_stream),
      .word_idx_o  (walk_word_idx),
      .hdr_done_o  (walk_done),
      .proto_o     (walk_proto),
      .frag_o      (walk_frag),
      .l4_pos_o    (walk_l4_pos)
  );

  always_ff @(posedge clk) begin
    if (rst) begin
      v4_done_q <= 1'b0;
    end else begin
      v4_done_q <= v4_done;
    end
  end

  always_ff @(posedge clk) begin
    v4_proto_q  <= v4_proto;
    v4_frag_q   <= v4_frag;
    v4_l4_pos_q <= v4_l4_pos;
  end

  always_comb begin
    l4_hdr_done = v4_done_q || walk_done;
    l4_proto    = v4_done_q ? v4_proto_q : walk_proto;
    l4_frag     = v4_done_q ? v4_frag_q : walk_frag;
    l4_pos      = v4_done_q ? v4_l4_pos_q : walk_l4_pos;
  end

  l4_parser l4_parser_inst (
      .clk         (clk),
      .rst         (rst),
      .eth_stream_i(walk_stream),
      .word_idx_i  (walk_word_idx),
      .hdr_done_i  (l4_hdr_done),
      .proto_i     (l4_proto),
      .frag_i      (l4_frag),
      .l4_pos_i    (l4_pos),
      .eth_stream_o(l4_stream),
      .word_idx_o  (),
      .hdr_done_o  (ports_done),
      .src_port_o  (src_port),
      .dst_port_o  (dst_port),
      .proto_o     (ports_proto)
  );

  always_comb begin
    meta_d       = meta_q;
    meta_valid_d = 1'b0;

    if (v6_stream.valid && v6_stream.last) begin
      meta_d.ip_v4    = v4_done;
      meta_d.ip_v6    = v6_done;
      meta_d.src_addr = v6_done ? v6_src_addr : ADDR_W'(v4_src_addr);
      meta_d.dst_addr = v6_done ? v6_dst_addr : ADDR_W'(v4_dst_addr);
    end

    if (l4_stream.valid && l4_stream.last) begin
      meta_d.ports_valid = ports_done;
      meta_d.l4_proto    = ports_proto;
      meta_d.src_port    = src_port;
      meta_d.dst_port    = dst_port;
      meta_valid_d       = 1'b1;
    end
  end

  always_ff @(posedge clk) begin
    if (rst) begin
      meta_valid_q   <= 1'b0;
      stream_valid_q <= 1'b0;
    end else begin
      meta_valid_q   <= meta_valid_d;
      stream_valid_q <= l4_stream.valid;
    end
  end

  always_ff @(posedge clk) begin
    meta_q   <= meta_d;
    stream_q <= l4_stream;
  end

  always_comb begin
    eth_stream_o       = stream_q;
    eth_stream_o.valid = stream_valid_q;
  end

  assign meta_valid_o = meta_valid_q;
  assign meta_o       = meta_q;

endmodule
