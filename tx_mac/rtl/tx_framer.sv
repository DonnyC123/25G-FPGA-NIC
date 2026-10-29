module tx_framer
  import pcs_pkg::*;
  import crc32_pkg::*;
#(
  parameter int MIN_FRAME_BYTES = 60
) (
  input  logic                     clk,
  input  logic                     rst,
         tx_eth_stream_if.slave    tx_stream_i,
  input  logic                     out_ready_i,
  output logic [PCS_PAYLOAD_W-1:0] out_data_o,
  output logic [PCS_SYNC_W-1:0]    out_control_o,
  output logic                     out_valid_o
);

  localparam int POS_W     = LAST_BYTES_W + 1;
  localparam int GAP_BYTES = IPG_MIN - PCS_PAYLOAD_BYTES;

  typedef enum logic [2:0] {
    IDLE,
    DATA,
    PAD,
    TERM,
    GAP
  } state_t;

  if (tx_stream_i.DATA_W != PCS_PAYLOAD_W) begin : g_width_check
    $error("tx_framer expects a %0d-bit tx_stream_i, got %0d", PCS_PAYLOAD_W, tx_stream_i.DATA_W);
  end

  state_t                   state_d;
  state_t                   state_q;

  logic [CRC_W-1:0]         crc_d;
  logic [CRC_W-1:0]         crc_q;

  logic [PCS_PAYLOAD_W-1:0] term_block_d;
  logic [PCS_PAYLOAD_W-1:0] term_block_q;

  logic                     extra_gap_d;
  logic                     extra_gap_q;

  logic [PCS_PAYLOAD_W-1:0] out_data_d;
  logic [PCS_PAYLOAD_W-1:0] out_data_q;

  logic [PCS_SYNC_W-1:0]    out_control_d;
  logic [PCS_SYNC_W-1:0]    out_control_q;

  logic                     out_valid_d;
  logic                     out_valid_q;

  logic [PCS_PAYLOAD_W-1:0] payload;
  logic [POS_W-1:0]         word_bytes;
  logic                     count_clear;
  logic                     count_step;
  logic [POS_W-1:0]         end_pos;
  logic                     frame_done;

  logic [CRC_W-1:0]         crc_next;
  logic [PCS_PAYLOAD_W-1:0] data_block;
  logic [PCS_PAYLOAD_W-1:0] term_block;
  logic [LAST_BYTES_W-1:0]  term_bytes;
  logic                     fcs_fits;

  logic [PCS_PAYLOAD_W-1:0] end_data;
  logic [PCS_SYNC_W-1:0]    end_control;
  state_t                   end_state;
  logic                     long_gap;

  always_comb begin
    payload    = tx_stream_i.data;
    word_bytes = POS_W'(PCS_PAYLOAD_BYTES);
    for (int b = 0; b < PCS_PAYLOAD_BYTES; b++) begin
      if (tx_stream_i.last && tx_stream_i.LAST_BYTES_W'(b) >= tx_stream_i.last_bytes) begin
        payload[b*BYTE_W +: BYTE_W] = '0;
      end
    end
    if (tx_stream_i.last) begin
      word_bytes = POS_W'(tx_stream_i.last_bytes);
    end
    if (state_q == PAD) begin
      payload    = '0;
      word_bytes = '0;
    end
  end

  tx_pad_counter #(
      .MIN_FRAME_BYTES(MIN_FRAME_BYTES)
  ) tx_pad_counter_inst (
      .clk         (clk),
      .rst         (rst),
      .clear_i     (count_clear),
      .step_i      (count_step),
      .word_bytes_i(word_bytes),
      .end_pos_o   (end_pos),
      .done_o      (frame_done)
  );

  tx_fcs_encoder tx_fcs_encoder_inst (
      .crc_i       (crc_q),
      .data_i      (payload),
      .end_pos_i   (end_pos),
      .crc_next_o  (crc_next),
      .data_block_o(data_block),
      .term_block_o(term_block),
      .term_bytes_o(term_bytes),
      .fcs_fits_o  (fcs_fits)
  );

  always_comb begin
    end_data    = data_block;
    end_control = DATA_SYNC;
    end_state   = TERM;
    if (fcs_fits) begin
      end_data    = term_block;
      end_control = CTRL_SYNC;
      end_state   = GAP;
    end
    long_gap = term_bytes >= LAST_BYTES_W'(GAP_BYTES);
  end

  always_comb begin
    state_d           = state_q;
    crc_d             = crc_q;
    term_block_d      = term_block_q;
    extra_gap_d       = extra_gap_q;

    out_data_d        = IDLE_BLOCK;
    out_control_d     = CTRL_SYNC;
    out_valid_d       = 1'b0;

    count_clear       = 1'b0;
    count_step        = 1'b0;

    tx_stream_i.ready = 1'b0;

    if (out_ready_i) begin
      out_valid_d = 1'b1;

      unique case (state_q)
        IDLE: begin
          count_clear = 1'b1;
          crc_d       = CRC_INIT;
          if (tx_stream_i.valid) begin
            out_data_d = START_BLOCK;
            state_d    = DATA;
          end
        end

        DATA: begin
          tx_stream_i.ready = 1'b1;
          out_valid_d       = tx_stream_i.valid;
          if (tx_stream_i.valid) begin
            out_data_d    = payload;
            out_control_d = DATA_SYNC;
            crc_d         = crc_next;
            count_step    = 1'b1;
            if (tx_stream_i.last) begin
              state_d = PAD;
            end
            if (tx_stream_i.last && frame_done) begin
              out_data_d    = end_data;
              out_control_d = end_control;
              term_block_d  = term_block;
              extra_gap_d   = long_gap;
              state_d       = end_state;
            end
          end
        end

        PAD: begin
          out_data_d    = payload;
          out_control_d = DATA_SYNC;
          crc_d         = crc_next;
          count_step    = 1'b1;
          if (frame_done) begin
            out_data_d    = end_data;
            out_control_d = end_control;
            term_block_d  = term_block;
            extra_gap_d   = long_gap;
            state_d       = end_state;
          end
        end

        TERM: begin
          out_data_d = term_block_q;
          state_d    = GAP;
        end

        GAP: begin
          extra_gap_d = 1'b0;
          if (!extra_gap_q) begin
            state_d = IDLE;
          end
        end

        default: begin
          state_d = IDLE;
        end
      endcase
    end
  end

  always_ff @(posedge clk) begin
    if (rst) begin
      state_q     <= IDLE;
      crc_q       <= CRC_INIT;
      extra_gap_q <= 1'b0;
      out_valid_q <= 1'b0;
    end else begin
      state_q     <= state_d;
      crc_q       <= crc_d;
      extra_gap_q <= extra_gap_d;
      out_valid_q <= out_valid_d;
    end
  end

  always_ff @(posedge clk) begin
    term_block_q  <= term_block_d;
    out_data_q    <= out_data_d;
    out_control_q <= out_control_d;
  end

  always_comb begin
    out_data_o    = out_data_q;
    out_control_o = out_control_q;
    out_valid_o   = out_valid_q;
  end

endmodule
