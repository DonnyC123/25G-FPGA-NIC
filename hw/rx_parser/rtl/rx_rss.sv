module rx_rss
  import pcs_pkg::*;
  import parser_pkg::*;
(
  input  logic                             clk,
  input  logic                             rst,
  input  rx_eth_stream_t                   eth_stream_i,
  input  logic           [RSS_KEY_W-1:0]   rss_key_i,
  input  logic                             udp_ports_en_i,
  input  logic                             reta_we_i,
  input  logic           [RETA_ADDR_W-1:0] reta_addr_i,
  input  logic           [RSS_QUEUE_W-1:0] reta_queue_i,
  output rx_eth_stream_t                   eth_stream_o,
  output logic                             rss_valid_o,
  output rss_meta_t                        rss_o
);

  localparam int GROUP_BITS  = RSS_TUPLE_W / RSS_HASH_GROUPS;
  localparam int IPV4_ADDR_W = IPV4_ADDR_LEN * BYTE_W;
  localparam int IPV6_ADDR_W = IPV6_ADDR_LEN * BYTE_W;
  localparam int PORTS_W     = PORTS_BYTES * BYTE_W;

  rx_eth_stream_t                                       parse_stream;
  logic                                                 parse_valid;
  rx_parse_meta_t                                       parse_meta;

  logic                                                 is_tcp;
  logic                                                 is_udp;
  logic                                                 use_ports;
  rss_hash_type_t                                       hash_type_d;
  rss_hash_type_t                                       hash_type;
  logic                                                 hash_valid;

  logic           [RSS_TUPLE_W-1:0]                     tuple_d;
  logic           [RSS_TUPLE_W-1:0]                     tuple_q;

  logic           [RSS_HASH_GROUPS-1:0][RSS_HASH_W-1:0] partial_hash_d;
  logic           [RSS_HASH_GROUPS-1:0][RSS_HASH_W-1:0] partial_hash_q;

  logic           [RSS_HASH_W-1:0]                      hash_d;
  logic           [RSS_HASH_W-1:0]                      hash_q;

  logic           [RSS_QUEUE_W-1:0]                     reta_q         [RETA_SIZE];

  rss_meta_t                                            rss_d;
  rss_meta_t                                            rss_q;
  logic                                                 rss_valid_q;

  rx_parser rx_parser_inst (
      .clk         (clk),
      .rst         (rst),
      .eth_stream_i(eth_stream_i),
      .eth_stream_o(parse_stream),
      .meta_valid_o(parse_valid),
      .meta_o      (parse_meta)
  );

  always_comb begin
    is_tcp    = parse_meta.l4_proto == IP_PROTO_TCP;
    is_udp    = parse_meta.l4_proto == IP_PROTO_UDP;
    use_ports = parse_meta.ports_valid && (is_tcp || (is_udp && udp_ports_en_i));
  end

  always_comb begin
    tuple_d     = '0;
    hash_type_d = RSS_HASH_NONE;

    unique0 if (parse_meta.ip_v6) begin
      tuple_d[RSS_TUPLE_W-1-:2*IPV6_ADDR_W] = {parse_meta.src_addr, parse_meta.dst_addr};
      if (use_ports) begin
        tuple_d[RSS_TUPLE_W-1-2*IPV6_ADDR_W-:PORTS_W] = {parse_meta.src_port, parse_meta.dst_port};
      end
    end else if (parse_meta.ip_v4) begin
      tuple_d[RSS_TUPLE_W-1-:2*IPV4_ADDR_W] = {
        parse_meta.src_addr[IPV4_ADDR_W-1:0], parse_meta.dst_addr[IPV4_ADDR_W-1:0]
      };
      if (use_ports) begin
        tuple_d[RSS_TUPLE_W-1-2*IPV4_ADDR_W-:PORTS_W] = {parse_meta.src_port, parse_meta.dst_port};
      end
    end

    if (parse_meta.ip_v4 || parse_meta.ip_v6) begin
      hash_type_d = use_ports ? RSS_HASH_L4 : RSS_HASH_L3;
    end
  end

  always_comb begin
    partial_hash_d = '0;

    for (int g = 0; g < RSS_HASH_GROUPS; g++) begin
      for (int i = 0; i < GROUP_BITS; i++) begin
        if (tuple_q[RSS_TUPLE_W-1-(g*GROUP_BITS+i)]) begin
          partial_hash_d[g] = partial_hash_d[g] ^ rss_key_i[RSS_KEY_W-1-(g*GROUP_BITS+i)-:RSS_HASH_W];
        end
      end
    end

    hash_d = '0;
    for (int g = 0; g < RSS_HASH_GROUPS; g++) begin
      hash_d = hash_d ^ partial_hash_q[g];
    end
  end

  data_status_pipeline #(
      .DATA_W    ($bits(rss_hash_type_t)),
      .STATUS_W  (1),
      .PIPE_DEPTH(RSS_STAGES - 1)
  ) hash_type_pipeline_inst (
      .clk     (clk),
      .rst     (rst),
      .data_i  (hash_type_d),
      .status_i(parse_valid),
      .data_o  (hash_type),
      .status_o(hash_valid)
  );

  always_ff @(posedge clk) begin
    if (reta_we_i) begin
      reta_q[reta_addr_i] <= reta_queue_i;
    end
  end

  always_comb begin
    rss_d.hash_type = hash_type;
    rss_d.hash      = '0;
    rss_d.rx_queue  = '0;

    if (hash_type != RSS_HASH_NONE) begin
      rss_d.hash     = hash_q;
      rss_d.rx_queue = reta_q[hash_q[RETA_ADDR_W-1:0]];
    end
  end

  always_ff @(posedge clk) begin
    if (rst) begin
      rss_valid_q    <= 1'b0;
      tuple_q        <= 'x;
      partial_hash_q <= 'x;
      hash_q         <= 'x;
      rss_q          <= 'x;
    end else begin
      rss_valid_q    <= hash_valid;
      tuple_q        <= tuple_d;
      partial_hash_q <= partial_hash_d;
      hash_q         <= hash_d;
      rss_q          <= rss_d;
    end
  end

  data_status_pipeline #(
      .DATA_W    ($bits(parse_stream.data) + $bits(parse_stream.last_bytes) + $bits(parse_stream.last)),
      .STATUS_W  ($bits(parse_stream.valid) + $bits(parse_stream.drop)),
      .PIPE_DEPTH(RSS_STAGES)
  ) stream_pipeline_inst (
      .clk     (clk),
      .rst     (rst),
      .data_i  ({parse_stream.data, parse_stream.last_bytes, parse_stream.last}),
      .status_i({parse_stream.valid, parse_stream.drop}),
      .data_o  ({eth_stream_o.data, eth_stream_o.last_bytes, eth_stream_o.last}),
      .status_o({eth_stream_o.valid, eth_stream_o.drop})
  );

  assign rss_valid_o = rss_valid_q;
  assign rss_o       = rss_q;

endmodule
