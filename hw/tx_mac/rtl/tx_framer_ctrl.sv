module tx_framer_ctrl
  import pcs_pkg::*;
  import crc32_pkg::*;
  import pcs_pkg::BYTE_W;
#(
  parameter  int MIN_FRAME_BYTES = 60,
  localparam int POS_W           = LAST_BYTES_W + 1
) (
  input  logic                     clk,
  input  logic                     rst,
         tx_eth_stream_if.slave    tx_stream_i,
  input  logic                     out_ready_i,

  output logic [PCS_PAYLOAD_W-1:0] data_o,
  output logic [PCS_SYNC_W-1:0]    control_o,
  output logic                     valid_o,
  output logic                     end_o,
  output logic                     term_o,
  output logic [CRC_W-1:0]         fcs_o,
  output logic [POS_W-1:0]         end_pos_o,
  output logic [LAST_BYTES_W-1:0]  term_bytes_o,
  output logic                     fcs_fits_o
);

  localparam int GAP_BYTES = IPG_MIN - PCS_PAYLOAD_BYTES;

  typedef enum logic [2:0] {
    IDLE,
    DATA,
    PAD,
    TERM,
    GAP
  } state_t;

  state_t                   state_d;
  state_t                   state_q;

  logic [CRC_W-1:0]         crc_d;
  logic [CRC_W-1:0]         crc_q;

  logic                     extra_gap_d;
  logic                     extra_gap_q;

  logic [PCS_PAYLOAD_W-1:0] data_d;
  logic [PCS_PAYLOAD_W-1:0] data_q;

  logic [PCS_SYNC_W-1:0]    control_d;
  logic [PCS_SYNC_W-1:0]    control_q;

  logic                     valid_d;
  logic                     valid_q;

  logic                     end_d;
  logic                     end_q;

  logic                     term_d;
  logic                     term_q;

  logic [CRC_W-1:0]         fcs_q;
  logic [POS_W-1:0]         end_pos_q;
  logic [LAST_BYTES_W-1:0]  term_bytes_q;
  logic                     fcs_fits_q;

  logic [PCS_PAYLOAD_W-1:0] payload;
  logic [POS_W-1:0]         word_bytes;
  logic                     count_clear;
  logic                     count_step;
  logic [POS_W-1:0]         end_pos;
  logic                     frame_done;

  logic [CRC_W-1:0]         crc_next;
  logic [CRC_W-1:0]         fcs;
  logic [LAST_BYTES_W-1:0]  term_bytes;
  logic                     fcs_fits;

  logic [PCS_SYNC_W-1:0]    end_control;
  state_t                   end_state;
  logic                     long_gap;

  logic                     advance;

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
      .fcs_o       (fcs),
      .term_bytes_o(term_bytes),
      .fcs_fits_o  (fcs_fits)
  );

  always_comb begin
    end_control = DATA_SYNC;
    end_state   = TERM;
    if (fcs_fits) begin
      end_control = CTRL_SYNC;
      end_state   = GAP;
    end
    long_gap = term_bytes >= LAST_BYTES_W'(GAP_BYTES);
  end

  always_comb begin
    advance           = !valid_q || out_ready_i;

    state_d           = state_q;
    crc_d             = crc_q;
    extra_gap_d       = extra_gap_q;

    data_d            = data_q;
    control_d         = control_q;
    valid_d           = valid_q;
    end_d             = end_q;
    term_d            = term_q;

    count_clear       = 1'b0;
    count_step        = 1'b0;

    tx_stream_i.ready = 1'b0;

    if (advance) begin
      data_d    = IDLE_BLOCK;
      control_d = CTRL_SYNC;
      valid_d   = 1'b1;
      end_d     = 1'b0;
      term_d    = 1'b0;

      unique case (state_q)
        IDLE: begin
          count_clear = 1'b1;
          crc_d       = CRC_INIT;
          if (tx_stream_i.valid) begin
            data_d  = START_BLOCK;
            state_d = DATA;
          end
        end

        DATA: begin
          tx_stream_i.ready = 1'b1;
          valid_d           = tx_stream_i.valid;
          if (tx_stream_i.valid) begin
            data_d     = payload;
            control_d  = DATA_SYNC;
            crc_d      = crc_next;
            count_step = 1'b1;
            if (tx_stream_i.last) begin
              state_d = PAD;
            end
            if (tx_stream_i.last && frame_done) begin
              control_d   = end_control;
              end_d       = 1'b1;
              extra_gap_d = long_gap;
              state_d     = end_state;
            end
          end
        end

        PAD: begin
          data_d     = payload;
          control_d  = DATA_SYNC;
          crc_d      = crc_next;
          count_step = 1'b1;
          if (frame_done) begin
            control_d   = end_control;
            end_d       = 1'b1;
            extra_gap_d = long_gap;
            state_d     = end_state;
          end
        end

        TERM: begin
          term_d  = 1'b1;
          state_d = GAP;
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
      valid_q     <= 1'b0;
      end_q       <= 1'b0;
      term_q      <= 1'b0;
    end else begin
      state_q     <= state_d;
      crc_q       <= crc_d;
      extra_gap_q <= extra_gap_d;
      valid_q     <= valid_d;
      end_q       <= end_d;
      term_q      <= term_d;
    end
  end

  always_ff @(posedge clk) begin
    data_q    <= data_d;
    control_q <= control_d;
    if (advance) begin
      fcs_q        <= fcs;
      end_pos_q    <= end_pos;
      term_bytes_q <= term_bytes;
      fcs_fits_q   <= fcs_fits;
    end
  end

  always_comb begin
    data_o       = data_q;
    control_o    = control_q;
    valid_o      = valid_q;
    end_o        = end_q;
    term_o       = term_q;
    fcs_o        = fcs_q;
    end_pos_o    = end_pos_q;
    term_bytes_o = term_bytes_q;
    fcs_fits_o   = fcs_fits_q;
  end

endmodule
