package pcs_pkg;
  localparam int BYTE_W                 = 8;
  localparam int PCS_PAYLOAD_BYTES      = 8;
  localparam int SOF_L4_PAYLOAD_BYTES   = 4;
  localparam int PCS_PAYLOAD_W          = PCS_PAYLOAD_BYTES * BYTE_W;
  localparam int PCS_SYNC_W             = 2;
  localparam int PCS_BLOCK_W            = PCS_PAYLOAD_W + PCS_SYNC_W;
  localparam int CTRL_SYMBOL_W          = 7;
  localparam int O_CODE_W               = 4;
  localparam int OS_DATA_BYTES          = 3;

  localparam int PCS_CTRL_DATA_SYMBOL_W = PCS_PAYLOAD_BYTES - 1;
  localparam int PCS_CTRL_SYMBOL_W      = (PCS_CTRL_DATA_SYMBOL_W * BYTE_W) / CTRL_SYMBOL_W;

  localparam int XCODE_BLOCKS           = 4;
  localparam int XCODE_HDR_W            = 1;
  localparam int XCODE_PAYLOAD_W        = XCODE_BLOCKS * PCS_PAYLOAD_W;
  localparam int XCODE_BLOCK_W          = XCODE_PAYLOAD_W + XCODE_HDR_W;

  typedef struct packed {
    logic [OS_DATA_BYTES-1:0][BYTE_W-1:0] data_l4;
    logic [O_CODE_W-1:0]                  o_code_l4;
    logic [O_CODE_W-1:0]                  o_code_l0;
    logic [OS_DATA_BYTES-1:0][BYTE_W-1:0] data_l0;
  } pcs_os_fields_t;

  typedef union packed {
    logic [PCS_CTRL_DATA_SYMBOL_W-1:0][BYTE_W-1:0]   data;
    logic [PCS_CTRL_SYMBOL_W-1:0][CTRL_SYMBOL_W-1:0] ctrl;
    pcs_os_fields_t                                  os;
  } pcs_fields_t;

  typedef struct packed {
    pcs_fields_t       fields;
    logic [BYTE_W-1:0] block_type;
  } pcs_ctrl_payload_t;

  typedef struct packed {
    pcs_ctrl_payload_t     payload;
    logic [PCS_SYNC_W-1:0] sync;
  } pcs_66b_block_t;

  typedef struct packed {
    logic [XCODE_PAYLOAD_W-1:0] payload;
    logic [XCODE_HDR_W-1:0]     hdr;
  } pcs_257b_block_t;

  localparam int ETH_DATA_BYTES = PCS_PAYLOAD_BYTES;
  localparam int ETH_DATA_W     = ETH_DATA_BYTES * BYTE_W;
  localparam int LAST_BYTES_W   = $clog2(ETH_DATA_BYTES);

  typedef struct packed {
    logic [ETH_DATA_W-1:0]   data;
    logic [LAST_BYTES_W-1:0] last_bytes;
    logic                    valid;
    logic                    last;
    logic                    drop;
  } rx_eth_stream_t;

  typedef struct packed {
    logic unexpected_eof;
    logic ctrl_parsing;
    logic unexpected_sync;
    logic invalid_sync;
  } pcs_decoder_error_t;

  // IEEE 802.3 Clause 49 block-type fields
  // S = start, T = terminate, O = ordered set, D = data, C = control (idle/error)
  localparam logic [7:0] IDLE_BLK = 8'h1E;  // C0..C7
  localparam logic [7:0] SOF_L0 = 8'h78;  // S0 D1..D7           (start in lane 0)
  localparam logic [7:0] SOF_L4 = 8'h33;  // C0..C3 S4 D5..D7    (start in lane 4)
  localparam logic [7:0] OS_SOF_L4 = 8'h66;  // O0 D1..D3 S4 D5..D7 (ordered set, then start lane)
  localparam logic [7:0] OS_OS = 8'h55;  // O0 D1..D3 O4 D5..D7 (ordered sets in both halves)
  localparam logic [7:0] OS_L0 = 8'h4B;  // O0 D1..D3 C4..C7    (ordered set, then control)
  localparam logic [7:0] OS_L4 = 8'h2D;  // C0..C3 O4 D5..D7    (control, then ordered set 4)
  localparam logic [7:0] TERM_L0 = 8'h87;  // T0 C1..C7
  localparam logic [7:0] TERM_L1 = 8'h99;  // D0 T1 C2..C7
  localparam logic [7:0] TERM_L2 = 8'hAA;  // D0 D1 T2 C3..C7
  localparam logic [7:0] TERM_L3 = 8'hB4;  // D0..D2 T3 C4..C7
  localparam logic [7:0] TERM_L4 = 8'hCC;  // D0..D3 T4 C5..C7
  localparam logic [7:0] TERM_L5 = 8'hD2;  // D0..D4 T5 C6..C7
  localparam logic [7:0] TERM_L6 = 8'hE1;  // D0..D5 T6 C7
  localparam logic [7:0] TERM_L7 = 8'hFF;  // D0..D6 T7

  localparam logic [PCS_PAYLOAD_BYTES-1:0][7:0] TERM_TYPES = {
      TERM_L7, TERM_L6, TERM_L5, TERM_L4, TERM_L3, TERM_L2, TERM_L1, TERM_L0
  };

  localparam logic [7:0]               PREAMBLE_BYTE = 8'h55;
  localparam logic [7:0]               SFD_BYTE      = 8'hD5;
  localparam logic [PCS_PAYLOAD_W-1:0] IDLE_BLOCK    = {{PCS_CTRL_DATA_SYMBOL_W{8'h00}}, IDLE_BLK};
  localparam logic [PCS_PAYLOAD_W-1:0] START_BLOCK   = {SFD_BYTE, {(PCS_CTRL_DATA_SYMBOL_W-1){PREAMBLE_BYTE}}, SOF_L0};

  localparam logic [CTRL_SYMBOL_W-1:0] CTRL_IDLE = 7'h00;
  localparam logic [CTRL_SYMBOL_W-1:0] CTRL_LPI = 7'h06;
  localparam logic [CTRL_SYMBOL_W-1:0] CTRL_ERROR = 7'h1E;

  localparam logic [O_CODE_W-1:0] O_SEQ = 4'h0;
  localparam logic [O_CODE_W-1:0] O_SIG = 4'hF;

  localparam logic [PCS_SYNC_W-1:0] CTRL_SYNC = 2'b01;
  localparam logic [PCS_SYNC_W-1:0] DATA_SYNC = 2'b10;


  function automatic logic is_valid_sync(logic [PCS_SYNC_W-1:0] sync);
    return sync == CTRL_SYNC || sync == DATA_SYNC;
  endfunction

  localparam int IPG_MIN = 12;

endpackage
