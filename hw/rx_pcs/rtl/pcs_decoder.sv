module pcs_decoder
  import pcs_pkg::*;
(
  input  logic               clk,
  input  logic               rst,
  input  logic               valid_i,
  input  pcs_66b_block_t     pcs_block_i,
  input  logic               aligned_i,

  output rx_eth_stream_t     eth_stream_o,
  output pcs_decoder_error_t pcs_decoder_error_o
);

  localparam int BUFFER_BYTES      = SOF_L4_PAYLOAD_BYTES;
  localparam int BUFFER_W          = BUFFER_BYTES * BYTE_W;
  localparam int REM_BYTES         = PCS_CTRL_DATA_SYMBOL_W - BUFFER_BYTES;
  localparam int REM_BYTES_COUNT_W = $clog2(REM_BYTES + 1);
  localparam int DELAY_NEW_BYTES   = PCS_PAYLOAD_BYTES - BUFFER_BYTES;

  typedef enum int {
    IDLE,
    ACTIVE,
    SOF_DELAY,
    ACTIVE_DELAY,
    EOF_DELAY
  } decoder_state_t;

  typedef enum int {
    PARSE_SOF,
    PARSE_SOF_DELAY,
    PARSE_EOF,
    PARSE_IDLE,
    PARSE_ERROR
  } parser_state_t;

  parser_state_t                                         parser_state;

  decoder_state_t                                        decoder_state_d;
  decoder_state_t                                        decoder_state_q;
  pcs_decoder_error_t                                    pcs_decoder_error_d;
  pcs_decoder_error_t                                    pcs_decoder_error_q;
  rx_eth_stream_t                                        eth_stream_d;
  rx_eth_stream_t                                        eth_stream_q;

  logic                          [BUFFER_W-1:0]          delay_buffer_d;
  logic                          [BUFFER_W-1:0]          delay_buffer_q;

  logic                          [REM_BYTES_COUNT_W-1:0] rem_count_buffer_d;
  logic                          [REM_BYTES_COUNT_W-1:0] rem_count_buffer_q;

  type (eth_stream_d.last_bytes)                         eof_valid;
  logic                          [PCS_CTRL_SYMBOL_W-1:0] ctrl_check;
  logic                          [PCS_CTRL_SYMBOL_W-1:0] ctrl_valid;

  always_comb begin
    eof_valid  = '0;
    ctrl_check = '0;

    case (pcs_block_i.payload.block_type)
      IDLE_BLK: begin
        parser_state = PARSE_IDLE;
        ctrl_check   = 'b1111_1111;
      end
      SOF_L0: begin
        parser_state = PARSE_SOF;
      end
      SOF_L4: begin
        parser_state = PARSE_SOF_DELAY;
      end

      // Order set logic
      OS_SOF_L4: begin
        parser_state = PARSE_SOF_DELAY;
      end
      OS_OS: begin
        parser_state = PARSE_IDLE;
      end
      OS_L0: begin
        parser_state = PARSE_IDLE;
      end
      OS_L4: begin
        parser_state = PARSE_IDLE;
      end

      TERM_L0: begin
        parser_state = PARSE_EOF;
        eof_valid    = 'd0;
        ctrl_check   = 'b1111_1110;
      end
      TERM_L1: begin
        parser_state = PARSE_EOF;
        eof_valid    = 'd1;
        ctrl_check   = 'b1111_1100;
      end
      TERM_L2: begin
        parser_state = PARSE_EOF;
        eof_valid    = 'd2;
        ctrl_check   = 'b1111_1000;
      end
      TERM_L3: begin
        parser_state = PARSE_EOF;
        eof_valid    = 'd3;
        ctrl_check   = 'b1111_0000;
      end
      TERM_L4: begin
        parser_state = PARSE_EOF;
        eof_valid    = 'd4;
        ctrl_check   = 'b1110_0000;
      end
      TERM_L5: begin
        parser_state = PARSE_EOF;
        eof_valid    = 'd5;
        ctrl_check   = 'b1100_0000;
      end
      TERM_L6: begin
        parser_state = PARSE_EOF;
        eof_valid    = 'd6;
        ctrl_check   = 'b1000_0000;
      end
      TERM_L7: begin
        parser_state = PARSE_EOF;
        eof_valid    = 'd7;
      end
      default: begin
        parser_state = PARSE_ERROR;
      end
    endcase

    for (int i = 0; i < PCS_CTRL_SYMBOL_W; i++) begin
      ctrl_valid[i] = !ctrl_check[i] || pcs_block_i.payload.fields.ctrl[i] == CTRL_IDLE;
    end

    case (&ctrl_valid)
      1'b0:    parser_state = PARSE_ERROR;
      default: ;
    endcase
  end

  always_comb begin
    pcs_decoder_error_d = '0;
    decoder_state_d     = decoder_state_q;
    eth_stream_d        = 'x;
    eth_stream_d.valid  = '0;
    eth_stream_d.last   = '0;
    eth_stream_d.drop   = '0;
    rem_count_buffer_d  = '0;

    if (decoder_state_q == EOF_DELAY) begin
      eth_stream_d.data       = PCS_PAYLOAD_W'(delay_buffer_q[BUFFER_W-1:BYTE_W]);
      eth_stream_d.valid      = 1'b1;
      eth_stream_d.last       = 1'b1;
      eth_stream_d.last_bytes = LAST_BYTES_W'(rem_count_buffer_q);
      decoder_state_d         = IDLE;
    end
    delay_buffer_d = delay_buffer_q;
    if (valid_i) begin
      delay_buffer_d = pcs_block_i.payload[PCS_PAYLOAD_W-1-:BUFFER_W];
      unique case (decoder_state_q)
        IDLE, EOF_DELAY: begin
          case (pcs_block_i.sync)
            CTRL_SYNC: begin
              unique case (parser_state)
                PARSE_SOF:       decoder_state_d = ACTIVE;
                PARSE_SOF_DELAY: decoder_state_d = SOF_DELAY;
                PARSE_EOF:       pcs_decoder_error_d.unexpected_eof = 1'b1;
                PARSE_ERROR:     pcs_decoder_error_d.ctrl_parsing = 1'b1;
                PARSE_IDLE:      ;
              endcase
            end
            DATA_SYNC: pcs_decoder_error_d.unexpected_sync = 1'b1;
            default:   pcs_decoder_error_d.invalid_sync = 1'b1;
          endcase
        end

        ACTIVE: begin
          case (pcs_block_i.sync)
            CTRL_SYNC: begin
              eth_stream_d.data = {{BYTE_W{1'bx}}, pcs_block_i.payload.fields.data};  //only 7 bytes
              if (parser_state == PARSE_EOF) begin
                eth_stream_d.valid      = 1'b1;
                eth_stream_d.last       = 1'b1;
                eth_stream_d.last_bytes = eof_valid;
                decoder_state_d         = IDLE;
              end else begin
                pcs_decoder_error_d.ctrl_parsing = 1'b1;
                eth_stream_d.drop                = 1'b1;
                unique case (parser_state)
                  PARSE_SOF:       decoder_state_d = ACTIVE;
                  PARSE_SOF_DELAY: decoder_state_d = SOF_DELAY;
                  default:         decoder_state_d = IDLE;
                endcase
              end
            end
            DATA_SYNC: begin
              eth_stream_d.data  = pcs_block_i.payload;
              eth_stream_d.valid = 1'b1;
            end
            default: begin
              decoder_state_d                  = IDLE;
              pcs_decoder_error_d.invalid_sync = 1'b1;
              eth_stream_d.drop                = 1'b1;
            end
          endcase
        end
        SOF_DELAY: begin
          case (pcs_block_i.sync)
            CTRL_SYNC: begin
              pcs_decoder_error_d.ctrl_parsing = 1'b1;
              eth_stream_d.drop                = 1'b1;
              unique case (parser_state)
                PARSE_SOF:       decoder_state_d = ACTIVE;
                PARSE_SOF_DELAY: decoder_state_d = SOF_DELAY;
                default:         decoder_state_d = IDLE;
              endcase
            end
            DATA_SYNC: decoder_state_d = ACTIVE_DELAY;
            default: begin
              decoder_state_d                  = IDLE;
              pcs_decoder_error_d.invalid_sync = 1'b1;
              eth_stream_d.drop                = 1'b1;
            end
          endcase
        end
        ACTIVE_DELAY: begin
          case (pcs_block_i.sync)
            CTRL_SYNC: begin
              decoder_state_d = IDLE;
              if (parser_state == PARSE_EOF) begin
                eth_stream_d.valid = 1'b1;
                eth_stream_d.data = {
                  pcs_block_i.payload.fields.data[DELAY_NEW_BYTES-1:0], delay_buffer_q
                };
                if (eof_valid < LAST_BYTES_W'(DELAY_NEW_BYTES)) begin
                  eth_stream_d.last       = 1'b1;
                  eth_stream_d.last_bytes = LAST_BYTES_W'(BUFFER_BYTES + eof_valid);
                end else begin
                  rem_count_buffer_d = REM_BYTES_COUNT_W'(eof_valid - DELAY_NEW_BYTES);
                  decoder_state_d    = EOF_DELAY;
                end
              end else begin
                pcs_decoder_error_d.ctrl_parsing = 1'b1;
                eth_stream_d.drop                = 1'b1;
                unique case (parser_state)
                  PARSE_SOF:       decoder_state_d = ACTIVE;
                  PARSE_SOF_DELAY: decoder_state_d = SOF_DELAY;
                  default:         decoder_state_d = IDLE;
                endcase
              end
            end
            DATA_SYNC: begin
              eth_stream_d.valid = 1'b1;
              eth_stream_d.data  = {pcs_block_i.payload[BUFFER_W-1:0], delay_buffer_q};
            end
            default: begin
              decoder_state_d                  = IDLE;
              pcs_decoder_error_d.invalid_sync = 1'b1;
              eth_stream_d.drop                = 1'b1;
            end
          endcase
        end
      endcase
    end

    if (!aligned_i) begin
      decoder_state_d     = IDLE;
      pcs_decoder_error_d = '0;
      if (decoder_state_q inside {ACTIVE, SOF_DELAY, ACTIVE_DELAY}) begin
        eth_stream_d.drop = 1'b1;
      end
    end
  end

  always_ff @(posedge clk) begin
    if (rst) begin
      decoder_state_q    <= IDLE;
      rem_count_buffer_q <= '0;
      delay_buffer_q     <= 'x;
    end else begin
      decoder_state_q    <= decoder_state_d;
      rem_count_buffer_q <= rem_count_buffer_d;
      delay_buffer_q     <= delay_buffer_d;
    end
  end

  data_pipeline #(
      .DATA_W    ($bits(pcs_decoder_error_d)),
      .PIPE_DEPTH(1),
      .RST_EN    (1)
  ) u_error_pipeline_inst (
      .clk   (clk),
      .rst   (rst),
      .data_i(pcs_decoder_error_d),
      .data_o(pcs_decoder_error_q)
  );

  data_status_pipeline #(
      .DATA_W($bits(eth_stream_d.data) + $bits(eth_stream_d.last_bytes) + $bits(eth_stream_d.last)),
      .STATUS_W($bits(eth_stream_d.valid) + $bits(eth_stream_d.drop)),
      .PIPE_DEPTH(1)
  ) u_ether_stream_pipeline (
      .clk     (clk),
      .rst     (rst),
      .data_i  ({eth_stream_d.data, eth_stream_d.last_bytes, eth_stream_d.last}),
      .status_i({eth_stream_d.valid, eth_stream_d.drop}),
      .data_o  ({eth_stream_q.data, eth_stream_q.last_bytes, eth_stream_q.last}),
      .status_o({eth_stream_q.valid, eth_stream_q.drop})
  );

  assign eth_stream_o        = eth_stream_q;
  assign pcs_decoder_error_o = pcs_decoder_error_q;

endmodule
