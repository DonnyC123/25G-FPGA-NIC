package parser_pkg;
  localparam int OFF_W               = 17;
  localparam int ETHERTYPE_W         = 16;
  localparam int ETHERTYPE_BYTES     = ETHERTYPE_W / 8;
  localparam int ETH_TYPE_OFF        = 12;
  localparam int VLAN_TAG_BYTES      = 4;
  localparam int MAX_VLANS           = 2;
  localparam int ETHERTYPE_POSITIONS = MAX_VLANS + 1;
  localparam int VLAN_COUNT_W        = $clog2(MAX_VLANS + 1);
  localparam int FCS_BYTES           = 4;

  localparam logic [OFF_W-1:0] ETHERTYPE_POS_0 = OFF_W'(ETH_TYPE_OFF);
  localparam logic [OFF_W-1:0] ETHERTYPE_POS_1 = OFF_W'(ETH_TYPE_OFF + VLAN_TAG_BYTES);
  localparam logic [OFF_W-1:0] ETHERTYPE_POS_2 = OFF_W'(ETH_TYPE_OFF + 2 * VLAN_TAG_BYTES);

  localparam logic [OFF_W-1:0] IP_POS_0        = OFF_W'(ETH_TYPE_OFF + ETHERTYPE_BYTES);
  localparam logic [OFF_W-1:0] IP_POS_1        = OFF_W'(ETH_TYPE_OFF + VLAN_TAG_BYTES + ETHERTYPE_BYTES);
  localparam logic [OFF_W-1:0] IP_POS_2        = OFF_W'(ETH_TYPE_OFF + 2 * VLAN_TAG_BYTES + ETHERTYPE_BYTES);

  function automatic logic [OFF_W-1:0] ip_pos(input logic [VLAN_COUNT_W-1:0] vlan_count);
    case (int'(vlan_count))
      0:       return IP_POS_0;
      1:       return IP_POS_1;
      default: return IP_POS_2;
    endcase
  endfunction

  function automatic logic ip_at(input logic [OFF_W-1:0] pos, input logic [VLAN_COUNT_W-1:0] vlan_count,
                                 input logic [OFF_W-1:0] off);
    return (int'(vlan_count) == 0 && pos == IP_POS_0 + off) ||
           (int'(vlan_count) == 1 && pos == IP_POS_1 + off) ||
           (int'(vlan_count) == 2 && pos == IP_POS_2 + off);
  endfunction

  localparam logic [ETHERTYPE_W-1:0] ETHERTYPE_MIN  = 16'h0600;
  localparam logic [ETHERTYPE_W-1:0] ETHERTYPE_VLAN = 16'h8100;
  localparam logic [ETHERTYPE_W-1:0] ETHERTYPE_QINQ = 16'h88A8;
  localparam logic [ETHERTYPE_W-1:0] ETHERTYPE_IPV4 = 16'h0800;
  localparam logic [ETHERTYPE_W-1:0] ETHERTYPE_IPV6 = 16'h86DD;

  localparam int IP_LEN_W         = 16;
  localparam int IP_PROTO_W       = 8;
  localparam int IP_VERSION_W     = 4;

  localparam int IPV4_VERSION     = 4;
  localparam int IPV4_VER_IHL_OFF = 0;
  localparam int IPV4_FRAG_OFF    = 6;
  localparam int IPV4_PROTO_OFF   = 9;
  localparam int IPV4_ADDR_OFF    = 12;
  localparam int IPV4_MIN_IHL     = 5;
  localparam int IPV4_IHL_SHIFT   = 2;
  localparam int IPV4_IHL_W       = 4;
  localparam int IPV4_HDR_BYTES   = 20;

  localparam int IPV6_VERSION     = 6;
  localparam int IPV6_VER_OFF     = 0;
  localparam int IPV6_NH_OFF      = 6;
  localparam int IPV6_ADDR_OFF    = 8;
  localparam int IPV6_HDR_BYTES   = 40;

  localparam int IPV6_EXT_NH_OFF  = 0;
  localparam int IPV6_EXT_LEN_OFF = 1;
  localparam int IPV6_FRAG_OFF    = 2;
  localparam int IPV6_EXT_SHIFT   = 3;
  localparam int IPV6_AH_SHIFT    = 2;
  localparam int IPV6_FRAG_BYTES  = 8;
  localparam int IPV6_EXT_LEN_W   = 8;

  localparam int IPV4_ADDR_LEN    = 4;
  localparam int IPV6_ADDR_LEN    = 16;

  localparam int PORT_W           = 16;
  localparam int PORTS_BYTES      = 2 * PORT_W / 8;
  localparam int L4_SRC_PORT_OFF  = 0;
  localparam int L4_DST_PORT_OFF  = 2;

  localparam int CSUM_W           = 16;
  localparam int CSUM_BYTES       = CSUM_W / 8;
  localparam int CSUM_ACC_W       = 32;
  localparam int CSUM_FOLDS       = 2;

  function automatic logic [CSUM_W-1:0] csum_fold(input logic [CSUM_ACC_W-1:0] value);
    logic [CSUM_ACC_W-1:0] folded;
    folded = value;
    for (int i = 0; i < CSUM_FOLDS; i++) begin
      folded = CSUM_ACC_W'(folded[CSUM_W-1:0]) + CSUM_ACC_W'(folded[CSUM_ACC_W-1:CSUM_W]);
    end
    return folded[CSUM_W-1:0];
  endfunction

  localparam logic [IP_LEN_W-1:0]   IPV4_FRAG_MASK = 16'h3FFF;
  localparam logic [IP_LEN_W-1:0]   IPV6_FRAG_MASK = 16'hFFF9;

  localparam logic [IP_PROTO_W-1:0] IP_PROTO_HOPOPT   = 8'd0;
  localparam logic [IP_PROTO_W-1:0] IP_PROTO_TCP      = 8'd6;
  localparam logic [IP_PROTO_W-1:0] IP_PROTO_UDP      = 8'd17;
  localparam logic [IP_PROTO_W-1:0] IP_PROTO_ROUTING  = 8'd43;
  localparam logic [IP_PROTO_W-1:0] IP_PROTO_FRAGMENT = 8'd44;
  localparam logic [IP_PROTO_W-1:0] IP_PROTO_AH       = 8'd51;
  localparam logic [IP_PROTO_W-1:0] IP_PROTO_DSTOPTS  = 8'd60;

  function automatic logic is_ipv6_ext(input logic [IP_PROTO_W-1:0] proto);
    return proto == IP_PROTO_HOPOPT || proto == IP_PROTO_ROUTING || proto == IP_PROTO_FRAGMENT ||
           proto == IP_PROTO_AH || proto == IP_PROTO_DSTOPTS;
  endfunction

  typedef struct packed {
    logic                ip_en;
    logic [OFF_W-1:0]    ip_pos;
    logic [CSUM_W-1:0]   ip_csum;
    logic                l4_en;
    logic [OFF_W-1:0]    l4_pos;
    logic [CSUM_W-1:0]   l4_csum;
  } csum_result_t;

  localparam int RX_PARSE_LATENCY = 5;
  localparam int RX_CSUM_START    = ETH_TYPE_OFF + ETHERTYPE_BYTES;
  localparam int RX_CSUM_LATENCY  = 3;

  typedef struct packed {
    logic                            ip_v4;
    logic                            ip_v6;
    logic                            ports_valid;
    logic [IP_PROTO_W-1:0]           l4_proto;
    logic [IPV6_ADDR_LEN*8-1:0]      src_addr;
    logic [IPV6_ADDR_LEN*8-1:0]      dst_addr;
    logic [PORT_W-1:0]               src_port;
    logic [PORT_W-1:0]               dst_port;
  } rx_parse_meta_t;

  localparam int RSS_KEY_BYTES    = 40;
  localparam int RSS_KEY_W        = RSS_KEY_BYTES * 8;
  localparam int RSS_HASH_W       = 32;
  localparam int RSS_TUPLE_BYTES  = 2 * IPV6_ADDR_LEN + PORTS_BYTES;
  localparam int RSS_TUPLE_W      = RSS_TUPLE_BYTES * 8;
  localparam int RSS_HASH_GROUPS  = 6;
  localparam int RSS_MAX_QUEUES   = 4;
  localparam int RSS_QUEUE_W      = $clog2(RSS_MAX_QUEUES);
  localparam int RETA_SIZE        = 64;
  localparam int RETA_ADDR_W      = $clog2(RETA_SIZE);
  localparam int RSS_STAGES       = 4;
  localparam int RX_RSS_LATENCY   = RX_PARSE_LATENCY + RSS_STAGES;

  typedef enum logic [1:0] {
    RSS_HASH_NONE,
    RSS_HASH_L3,
    RSS_HASH_L4
  } rss_hash_type_t;

  typedef struct packed {
    rss_hash_type_t           hash_type;
    logic [RSS_HASH_W-1:0]    hash;
    logic [RSS_QUEUE_W-1:0]   rx_queue;
  } rss_meta_t;

endpackage
