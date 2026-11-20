package nic_regs_pkg;
  import rss_pkg::*;

  localparam int NIC_REGS_DATA_W        = 32;
  localparam int NIC_REGS_WORD_BYTES    = NIC_REGS_DATA_W / 8;
  localparam int NIC_REGS_ADDR_W        = 12;
  localparam int NIC_REGS_IDX_W         = NIC_REGS_ADDR_W - 2;

  localparam logic [NIC_REGS_DATA_W-1:0] NIC_REGS_VERSION = 32'h0001_0000;

  localparam int RSS_KEY_WORDS          = RSS_KEY_W / NIC_REGS_DATA_W;
  localparam int RETA_WORDS             = RETA_SIZE * RSS_QUEUE_W / NIC_REGS_DATA_W;
  localparam int RSS_REGS_WORDS         = 1 + RSS_KEY_WORDS + RETA_WORDS;
  localparam int RSS_CTRL_UDP_PORTS_BIT = 0;

  localparam int REG_VERSION_OFF        = 'h000;
  localparam int REG_RSS_CTRL_OFF       = 'h010;
  localparam int REG_RSS_KEY_OFF        = REG_RSS_CTRL_OFF + NIC_REGS_WORD_BYTES;
  localparam int REG_RETA_OFF           = REG_RSS_KEY_OFF + RSS_KEY_WORDS * NIC_REGS_WORD_BYTES;

  typedef struct packed {
    logic [RETA_SIZE-1:0][RSS_QUEUE_W-1:0]         reta;
    logic [RSS_KEY_WORDS-1:0][NIC_REGS_DATA_W-1:0] key;
    logic [NIC_REGS_DATA_W-1:0]                    ctrl;
  } rss_regs_t;

  typedef logic [RSS_REGS_WORDS-1:0][NIC_REGS_DATA_W-1:0] rss_words_t;

  typedef union packed {
    rss_regs_t  regs;
    rss_words_t words;
  } rss_cfg_t;

endpackage
