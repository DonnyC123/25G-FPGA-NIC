package rx_meta_pkg;
  localparam int RX_META_BYTES     = 32;
  localparam int RX_META_BYTE_W    = 8;
  localparam int RX_META_HASH_W    = 32;
  localparam int RX_META_CSUM_W    = 16;
  localparam int RX_META_HASH_OFF  = 0;
  localparam int RX_META_CSUM_OFF  = 4;
  localparam int RX_META_TYPE_OFF  = 6;
  localparam int RX_META_QUEUE_OFF = 7;

  typedef struct packed {
    logic [RX_META_HASH_W-1:0] hash;
    logic [RX_META_CSUM_W-1:0] csum;
    logic [RX_META_BYTE_W-1:0] hash_type;
    logic [RX_META_BYTE_W-1:0] rx_queue;
  } rx_meta_t;

  function automatic logic [RX_META_BYTES*RX_META_BYTE_W-1:0] rx_meta_beat(input rx_meta_t meta);
    logic [RX_META_BYTES-1:0][RX_META_BYTE_W-1:0] beat;
    beat = '0;
    for (int i = 0; i < RX_META_HASH_W / RX_META_BYTE_W; i++) begin
      beat[RX_META_HASH_OFF+i] = meta.hash[i*RX_META_BYTE_W+:RX_META_BYTE_W];
    end
    beat[RX_META_CSUM_OFF]   = meta.csum[RX_META_CSUM_W-1-:RX_META_BYTE_W];
    beat[RX_META_CSUM_OFF+1] = meta.csum[RX_META_BYTE_W-1:0];
    beat[RX_META_TYPE_OFF]   = meta.hash_type;
    beat[RX_META_QUEUE_OFF]  = meta.rx_queue;
    return beat;
  endfunction

endpackage
