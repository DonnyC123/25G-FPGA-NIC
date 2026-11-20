package parser_pkg;
  import pcs_pkg::LAST_BYTES_W;

  localparam int RX_MAX_FRAME_BYTES  = 16384;
  localparam int RX_OFF_W            = $clog2(RX_MAX_FRAME_BYTES);
  localparam int RX_WORD_IDX_W       = RX_OFF_W - LAST_BYTES_W;

  typedef logic [RX_OFF_W-1:0]      rx_off_t;
  typedef logic [RX_WORD_IDX_W-1:0] rx_word_idx_t;

  localparam int ETHERTYPE_W         = 16;
  localparam int ETHERTYPE_BYTES     = ETHERTYPE_W / 8;
  localparam int ETH_TYPE_OFF        = 12;
  localparam int VLAN_TAG_BYTES      = 4;
  localparam int MAX_VLANS           = 2;
  localparam int ETHERTYPE_POSITIONS = MAX_VLANS + 1;
  localparam int VLAN_COUNT_W        = $clog2(MAX_VLANS + 1);
  localparam int FCS_BYTES           = 4;

  localparam rx_off_t ETHERTYPE_POS_0 = RX_OFF_W'(ETH_TYPE_OFF);
  localparam rx_off_t ETHERTYPE_POS_1 = RX_OFF_W'(ETH_TYPE_OFF + VLAN_TAG_BYTES);
  localparam rx_off_t ETHERTYPE_POS_2 = RX_OFF_W'(ETH_TYPE_OFF + 2 * VLAN_TAG_BYTES);

  localparam rx_off_t IP_POS_0        = RX_OFF_W'(ETH_TYPE_OFF + ETHERTYPE_BYTES);
  localparam rx_off_t IP_POS_1        = RX_OFF_W'(ETH_TYPE_OFF + VLAN_TAG_BYTES + ETHERTYPE_BYTES);
  localparam rx_off_t IP_POS_2        = RX_OFF_W'(ETH_TYPE_OFF + 2 * VLAN_TAG_BYTES + ETHERTYPE_BYTES);

  function automatic rx_off_t ip_pos(input logic [VLAN_COUNT_W-1:0] vlan_count);
    case (int'(vlan_count))
      0:       return IP_POS_0;
      1:       return IP_POS_1;
      default: return IP_POS_2;
    endcase
  endfunction

  function automatic logic ip_at(input rx_off_t pos, input logic [VLAN_COUNT_W-1:0] vlan_count,
                                 input rx_off_t off);
    return (int'(vlan_count) == 0 && pos == IP_POS_0 + off) ||
           (int'(vlan_count) == 1 && pos == IP_POS_1 + off) ||
           (int'(vlan_count) == 2 && pos == IP_POS_2 + off);
  endfunction

  localparam logic [ETHERTYPE_W-1:0] ETHERTYPE_MIN    = 16'h0600;
  localparam logic [ETHERTYPE_W-1:0] ETHERTYPE_VLAN   = 16'h8100;
  localparam logic [ETHERTYPE_W-1:0] ETHERTYPE_QINQ   = 16'h88A8;
  localparam logic [ETHERTYPE_W-1:0] ETHERTYPE_IPV4   = 16'h0800;
  localparam logic [ETHERTYPE_W-1:0] ETHERTYPE_IPV6   = 16'h86DD;

  localparam int                     IP_LEN_W         = 16;
  localparam int                     IP_PROTO_W       = 8;
  localparam int                     IP_VERSION_W     = 4;

  localparam int                     IPV4_VERSION     = 4;
  localparam int                     IPV4_VER_IHL_OFF = 0;
  localparam int                     IPV4_FRAG_OFF    = 6;
  localparam int                     IPV4_PROTO_OFF   = 9;
  localparam int                     IPV4_ADDR_OFF    = 12;
  localparam int                     IPV4_MIN_IHL     = 5;
  localparam int                     IPV4_IHL_SHIFT   = 2;
  localparam int                     IPV4_IHL_W       = 4;
  localparam int                     IPV4_HDR_BYTES   = 20;

  localparam int                     IPV6_VERSION     = 6;
  localparam int                     IPV6_VER_OFF     = 0;
  localparam int                     IPV6_NH_OFF      = 6;
  localparam int                     IPV6_ADDR_OFF    = 8;
  localparam int                     IPV6_HDR_BYTES   = 40;

  localparam int                     IPV6_EXT_NH_OFF  = 0;
  localparam int                     IPV6_EXT_LEN_OFF = 1;
  localparam int                     IPV6_EXT_SHIFT   = 3;
  localparam int                     IPV6_AH_SHIFT    = 2;
  localparam int                     IPV6_EXT_LEN_W   = 8;

  localparam int                     IPV4_ADDR_LEN    = 4;
  localparam int                     IPV6_ADDR_LEN    = 16;

  localparam int                     PORT_W           = 16;
  localparam int                     PORTS_BYTES      = 2 * PORT_W / 8;
  localparam int                     L4_SRC_PORT_OFF  = 0;
  localparam int                     L4_DST_PORT_OFF  = 2;

  localparam logic [IP_LEN_W-1:0]   IPV4_FRAG_MASK    = 16'h3FFF;

  localparam logic [IP_PROTO_W-1:0] IP_PROTO_HOPOPT   = 8'd0;
  localparam logic [IP_PROTO_W-1:0] IP_PROTO_TCP      = 8'd6;
  localparam logic [IP_PROTO_W-1:0] IP_PROTO_UDP      = 8'd17;
  localparam logic [IP_PROTO_W-1:0] IP_PROTO_ROUTING  = 8'd43;
  localparam logic [IP_PROTO_W-1:0] IP_PROTO_FRAGMENT = 8'd44;
  localparam logic [IP_PROTO_W-1:0] IP_PROTO_AH       = 8'd51;
  localparam logic [IP_PROTO_W-1:0] IP_PROTO_DSTOPTS  = 8'd60;

  localparam int IPV6_EXT_WALK_LATENCY = 2;
  localparam int RX_PARSE_LATENCY      = IPV6_EXT_WALK_LATENCY + 4;
  localparam int RX_CSUM_START_OFF     = ETH_TYPE_OFF + ETHERTYPE_BYTES;
  localparam int RX_CSUM_HOLD_STAGES   = 1;
  localparam int RX_CSUM_SUM_STAGES    = 1;
  localparam int RX_CSUM_ACCUM_STAGES  = 1;
  localparam int RX_CSUM_LATENCY       = RX_CSUM_HOLD_STAGES + RX_CSUM_SUM_STAGES + RX_CSUM_ACCUM_STAGES;

  typedef struct packed {
    logic                       ip_v4;
    logic                       ip_v6;
    logic                       ports_valid;
    logic [IP_PROTO_W-1:0]      l4_proto;
    logic [IPV6_ADDR_LEN*8-1:0] src_addr;
    logic [IPV6_ADDR_LEN*8-1:0] dst_addr;
    logic [PORT_W-1:0]          src_port;
    logic [PORT_W-1:0]          dst_port;
  } rx_parse_meta_t;

endpackage
