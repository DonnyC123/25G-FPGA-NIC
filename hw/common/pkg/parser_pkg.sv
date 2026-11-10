package parser_pkg;
  localparam int OFF_W           = 17;
  localparam int ETHERTYPE_W     = 16;
  localparam int ETHERTYPE_BYTES = ETHERTYPE_W / 8;
  localparam int ETH_TYPE_OFF    = 12;
  localparam int VLAN_TAG_BYTES  = 4;
  localparam int MAX_VLANS       = 2;
  localparam int VLAN_COUNT_W    = $clog2(MAX_VLANS + 1);
  localparam int ETH_HDR_MAX     = ETH_TYPE_OFF + VLAN_TAG_BYTES * MAX_VLANS + ETHERTYPE_BYTES;

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
  localparam int IPV4_LEN_OFF     = 2;
  localparam int IPV4_FRAG_OFF    = 6;
  localparam int IPV4_PROTO_OFF   = 9;
  localparam int IPV4_ADDR_OFF    = 12;
  localparam int IPV4_MIN_IHL     = 5;
  localparam int IPV4_IHL_SHIFT   = 2;
  localparam int IPV4_HDR_BYTES   = 20;

  localparam int OPT_NOP_RUN      = 4;
  localparam int OPT_WINDOW       = OPT_NOP_RUN + 3;
  localparam int OPT_MIN_LEN      = 2;
  localparam int OPT_SRR_MIN_LEN  = 7;

  localparam int IPV6_VERSION     = 6;
  localparam int IPV6_VER_OFF     = 0;
  localparam int IPV6_LEN_OFF     = 4;
  localparam int IPV6_NH_OFF      = 6;
  localparam int IPV6_ADDR_OFF    = 8;
  localparam int IPV6_HDR_BYTES   = 40;

  localparam int IPV6_EXT_NH_OFF  = 0;
  localparam int IPV6_EXT_LEN_OFF = 1;
  localparam int IPV6_FRAG_OFF    = 2;
  localparam int IPV6_EXT_SHIFT   = 3;
  localparam int IPV6_AH_SHIFT    = 2;
  localparam int IPV6_FRAG_BYTES  = 8;

  localparam int TCP_DOFF_OFF     = 12;
  localparam int TCP_CSUM_OFF     = 16;
  localparam int TCP_MIN_DOFF     = 5;
  localparam int TCP_DOFF_SHIFT   = 2;

  localparam int UDP_LEN_OFF      = 4;
  localparam int UDP_CSUM_OFF     = 6;
  localparam int UDP_HDR_BYTES    = 8;

  localparam int CSUM_W           = 16;
  localparam int CSUM_BYTES       = CSUM_W / 8;
  localparam int IPV4_CSUM_OFF    = 10;
  localparam int IPV4_ADDR_LEN    = 4;
  localparam int IPV6_ADDR_LEN    = 16;

  localparam logic [7:0]            IPV4_OPT_EOL  = 8'h00;
  localparam logic [7:0]            IPV4_OPT_NOP  = 8'h01;
  localparam logic [7:0]            IPV4_OPT_LSRR = 8'h83;
  localparam logic [7:0]            IPV4_OPT_SSRR = 8'h89;

  localparam logic [IP_LEN_W-1:0]   IPV4_FRAG_MASK = 16'h3FFF;
  localparam logic [IP_LEN_W-1:0]   IPV6_FRAG_MASK = 16'hFFF9;

  localparam logic [IP_PROTO_W-1:0] IP_PROTO_HOPOPT   = 8'd0;
  localparam logic [IP_PROTO_W-1:0] IP_PROTO_TCP      = 8'd6;
  localparam logic [IP_PROTO_W-1:0] IP_PROTO_UDP      = 8'd17;
  localparam logic [IP_PROTO_W-1:0] IP_PROTO_ROUTING  = 8'd43;
  localparam logic [IP_PROTO_W-1:0] IP_PROTO_FRAGMENT = 8'd44;
  localparam logic [IP_PROTO_W-1:0] IP_PROTO_AH       = 8'd51;
  localparam logic [IP_PROTO_W-1:0] IP_PROTO_DSTOPTS  = 8'd60;

  typedef struct packed {
    logic [OFF_W-1:0]        pos;
    logic                    eth_ok;
    logic [ETHERTYPE_W-1:0]  ethertype;
    logic [VLAN_COUNT_W-1:0] vlan_count;
    logic [OFF_W-1:0]        payload_off;
    logic                    ip_ok;
    logic                    ip_v6;
    logic [OFF_W-1:0]        addr_off;
    logic                    l4_known;
    logic [IP_PROTO_W-1:0]   l4_proto;
    logic [OFF_W-1:0]        l4_off;
    logic [OFF_W-1:0]        l4_end;
    logic                    tcp_ok;
    logic                    udp_ok;
    logic                    csum_skip;
    logic [OFF_W-1:0]        csum_pos;
    logic                    opt_done;
    logic [OFF_W-1:0]        opt_off;
    logic                    dst_alt;
    logic [OFF_W-1:0]        dst_alt_off;
  } parse_meta_t;

  typedef struct packed {
    logic                ip_en;
    logic [OFF_W-1:0]    ip_pos;
    logic [CSUM_W-1:0]   ip_csum;
    logic                l4_en;
    logic [OFF_W-1:0]    l4_pos;
    logic [CSUM_W-1:0]   l4_csum;
  } csum_result_t;

endpackage
