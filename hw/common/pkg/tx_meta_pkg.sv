package tx_meta_pkg;
  localparam int TX_META_BYTES      = 32;
  localparam int TX_META_FIELD_W    = 16;
  localparam int TX_META_FLAGS_OFF  = 0;
  localparam int TX_META_START_OFF  = 2;
  localparam int TX_META_OFFSET_OFF = 4;
  localparam int TX_META_LEN_OFF    = 6;
  localparam int TX_META_CSUM_BIT   = 0;

  typedef struct packed {
    logic                       csum;
    logic [TX_META_FIELD_W-1:0] csum_start;
    logic [TX_META_FIELD_W-1:0] csum_offset;
    logic [TX_META_FIELD_W-1:0] frame_len;
  } tx_meta_t;

endpackage
