package rss_pkg;
  import parser_pkg::IPV6_ADDR_LEN;
  import parser_pkg::PORTS_BYTES;
  import parser_pkg::RX_PARSE_LATENCY;

  localparam int                   RSS_KEY_BYTES   = 40;
  localparam int                   RSS_KEY_W       = RSS_KEY_BYTES * 8;
  localparam logic [RSS_KEY_W-1:0] RSS_DEFAULT_KEY =
      320'h6d5a56da255b0ec24167253d43a38fb0d0ca2bcbae7b30b477cb2da38030f20c6a42b73bbeac01fa;
  localparam int                   RSS_HASH_W      = 32;
  localparam int                   RSS_TUPLE_BYTES = 2 * IPV6_ADDR_LEN + PORTS_BYTES;
  localparam int                   RSS_TUPLE_W     = RSS_TUPLE_BYTES * 8;
  localparam int                   RSS_HASH_GROUPS = 6;
  localparam int                   RSS_MAX_QUEUES  = 4;
  localparam int                   RSS_QUEUE_W     = $clog2(RSS_MAX_QUEUES);
  localparam int                   RETA_SIZE       = 64;
  localparam int                   RETA_ADDR_W     = $clog2(RETA_SIZE);
  localparam int                   RSS_STAGES      = 4;
  localparam int                   RX_RSS_LATENCY  = RX_PARSE_LATENCY + RSS_STAGES;

  typedef enum logic [1:0] {
    RSS_HASH_NONE,
    RSS_HASH_L3,
    RSS_HASH_L4
  } rss_hash_type_t;

  typedef struct packed {
    rss_hash_type_t         hash_type;
    logic [RSS_HASH_W-1:0]  hash;
    logic [RSS_QUEUE_W-1:0] rx_queue;
  } rss_meta_t;

endpackage
