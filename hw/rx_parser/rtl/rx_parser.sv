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

  localparam int IPV6_ADDR_W = IPV6_ADDR_LEN * BYTE_W;
  localparam int IPV4_ADDR_W = IPV4_ADDR_LEN * BYTE_W;
  localparam int L4_ALIGN    = IPV6_EXT_WALK_LATENCY + 1;

  rx_eth_stream_t                            eth_stream;
  rx_word_idx_t                              eth_word_idx;
  logic           [VLAN_COUNT_W-1:0]         eth_vlan_count;
  logic                                      eth_ip_v4;
  logic                                      eth_ip_v6;

  logic                                      ipv4_done;
  logic           [IPV4_ADDR_W-1:0]          ipv4_src_addr;
  logic           [IPV4_ADDR_W-1:0]          ipv4_dst_addr;
  logic           [IP_PROTO_W-1:0]           ipv4_proto;
  logic                                      ipv4_frag;
  rx_off_t                                   ipv4_l4_pos;

  rx_eth_stream_t                            ipv6_stream;
  rx_word_idx_t                              ipv6_word_idx;
  logic                                      ipv6_done;
  logic           [IPV6_ADDR_W-1:0]          ipv6_src_addr;
  logic           [IPV6_ADDR_W-1:0]          ipv6_dst_addr;
  logic           [IP_PROTO_W-1:0]           ipv6_proto;
  rx_off_t                                   ipv6_l4_pos;

  rx_eth_stream_t                            walk_stream;
  rx_word_idx_t                              walk_word_idx;
  logic                                      walk_done;
  logic           [IP_PROTO_W-1:0]           walk_proto;
  logic                                      walk_frag;
  rx_off_t                                   walk_l4_pos;

  logic                                      ipv4_done_q;
  logic           [IP_PROTO_W-1:0]           ipv4_proto_q;
  logic                                      ipv4_frag_q;
  rx_off_t                                   ipv4_l4_pos_q;

  logic           [IPV6_ADDR_W-1:0]          ip_src_addr;
  logic           [IPV6_ADDR_W-1:0]          ip_dst_addr;
  logic                                      l4_ip_v4;
  logic                                      l4_ip_v6;
  logic           [IPV6_ADDR_W-1:0]          l4_src_addr;
  logic           [IPV6_ADDR_W-1:0]          l4_dst_addr;

  logic                                      l4_hdr_done;
  logic           [IP_PROTO_W-1:0]           l4_proto;
  logic                                      l4_frag;
  rx_off_t                                   l4_pos;

  rx_eth_stream_t                            l4_stream;
  logic                                      ports_done;
  logic           [PORT_W-1:0]               src_port;
  logic           [PORT_W-1:0]               dst_port;
  logic           [IP_PROTO_W-1:0]           ports_proto;

  rx_parse_meta_t                            meta_d;
  rx_parse_meta_t                            meta_q;
  logic                                      meta_valid_d;
  logic                                      meta_valid_q;

  rx_eth_stream_t                            stream_q;
  logic                                      stream_valid_q;

  eth_parser eth_parser_inst (
      .clk         (clk),
      .rst         (rst),
      .eth_stream_i(eth_stream_i),
      .eth_stream_o(eth_stream),
      .word_idx_o  (eth_word_idx),
      .vlan_count_o(eth_vlan_count),
      .ip_v4_o     (eth_ip_v4),
      .ip_v6_o     (eth_ip_v6)
  );

  ipv4_parser ipv4_parser_inst (
      .clk         (clk),
      .rst         (rst),
      .eth_stream_i(eth_stream),
      .word_idx_i  (eth_word_idx),
      .vlan_count_i(eth_vlan_count),
      .ip_v4_i     (eth_ip_v4),
      .hdr_done_o  (ipv4_done),
      .src_addr_o  (ipv4_src_addr),
      .dst_addr_o  (ipv4_dst_addr),
      .proto_o     (ipv4_proto),
      .frag_o      (ipv4_frag),
      .l4_pos_o    (ipv4_l4_pos)
  );

  ipv6_parser ipv6_parser_inst (
      .clk         (clk),
      .rst         (rst),
      .eth_stream_i(eth_stream),
      .word_idx_i  (eth_word_idx),
      .vlan_count_i(eth_vlan_count),
      .ip_v6_i     (eth_ip_v6),
      .eth_stream_o(ipv6_stream),
      .word_idx_o  (ipv6_word_idx),
      .hdr_done_o  (ipv6_done),
      .src_addr_o  (ipv6_src_addr),
      .dst_addr_o  (ipv6_dst_addr),
      .proto_o     (ipv6_proto),
      .l4_pos_o    (ipv6_l4_pos)
  );

  ipv6_ext_walk ipv6_ext_walk_inst (
      .clk         (clk),
      .rst         (rst),
      .eth_stream_i(ipv6_stream),
      .word_idx_i  (ipv6_word_idx),
      .ip_v6_i     (ipv6_done),
      .proto_i     (ipv6_proto),
      .l4_pos_i    (ipv6_l4_pos),
      .eth_stream_o(walk_stream),
      .word_idx_o  (walk_word_idx),
      .hdr_done_o  (walk_done),
      .proto_o     (walk_proto),
      .frag_o      (walk_frag),
      .l4_pos_o    (walk_l4_pos)
  );

  data_status_pipeline #(
      .DATA_W    ($bits(ipv4_proto) + $bits(ipv4_frag) + $bits(ipv4_l4_pos)),
      .STATUS_W  ($bits(ipv4_done)),
      .PIPE_DEPTH(IPV6_EXT_WALK_LATENCY)
  ) ipv4_pipeline_inst (
      .clk     (clk),
      .rst     (rst),
      .data_i  ({ipv4_proto, ipv4_frag, ipv4_l4_pos}),
      .status_i(ipv4_done),
      .data_o  ({ipv4_proto_q, ipv4_frag_q, ipv4_l4_pos_q}),
      .status_o(ipv4_done_q)
  );

  always_comb begin
    ip_src_addr = ipv6_done ? ipv6_src_addr : IPV6_ADDR_W'(ipv4_src_addr);
    ip_dst_addr = ipv6_done ? ipv6_dst_addr : IPV6_ADDR_W'(ipv4_dst_addr);
  end

  data_status_pipeline #(
      .DATA_W    (2 * IPV6_ADDR_W),
      .STATUS_W  ($bits(ipv4_done) + $bits(ipv6_done)),
      .PIPE_DEPTH(L4_ALIGN)
  ) ip_pipeline_inst (
      .clk     (clk),
      .rst     (rst),
      .data_i  ({ip_src_addr, ip_dst_addr}),
      .status_i({ipv4_done, ipv6_done}),
      .data_o  ({l4_src_addr, l4_dst_addr}),
      .status_o({l4_ip_v4, l4_ip_v6})
  );

  always_comb begin
    l4_hdr_done = ipv4_done_q || walk_done;
    l4_proto    = ipv4_done_q ? ipv4_proto_q : walk_proto;
    l4_frag     = ipv4_done_q ? ipv4_frag_q : walk_frag;
    l4_pos      = ipv4_done_q ? ipv4_l4_pos_q : walk_l4_pos;
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
      .hdr_done_o  (ports_done),
      .src_port_o  (src_port),
      .dst_port_o  (dst_port),
      .proto_o     (ports_proto)
  );

  always_comb begin
    meta_d       = meta_q;
    meta_valid_d = 1'b0;

    if (l4_stream.valid && l4_stream.last) begin
      meta_d.ip_v4       = l4_ip_v4;
      meta_d.ip_v6       = l4_ip_v6;
      meta_d.src_addr    = l4_src_addr;
      meta_d.dst_addr    = l4_dst_addr;
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
