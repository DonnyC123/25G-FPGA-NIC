module tx_fcs_encoder
  import pcs_pkg::*;
  import crc32_pkg::*;
(
  input  logic [CRC_W-1:0]         crc_i,
  input  logic [PCS_PAYLOAD_W-1:0] data_i,
  input  logic [LAST_BYTES_W:0]    end_pos_i,
  output logic [CRC_W-1:0]         crc_next_o,
  output logic [PCS_PAYLOAD_W-1:0] data_block_o,
  output logic [PCS_PAYLOAD_W-1:0] term_block_o,
  output logic [LAST_BYTES_W-1:0]  term_bytes_o,
  output logic                     fcs_fits_o
);

  localparam int POS_W     = LAST_BYTES_W + 1;
  localparam int FCS_BYTES = CRC_W / BYTE_W;
  localparam int WIDE_W    = PCS_PAYLOAD_W + CRC_W;
  localparam int TERM_D_W  = PCS_PAYLOAD_W - BYTE_W;

  logic [CRC_W-1:0]    crc_by_bytes [PCS_PAYLOAD_BYTES];
  logic [CRC_W-1:0]    crc_end;
  logic [CRC_W-1:0]    fcs;
  logic [WIDE_W-1:0]   word_with_fcs;
  logic [TERM_D_W-1:0] term_data;

  crc32_word #(
      .BYTES(PCS_PAYLOAD_BYTES)
  ) crc32_word_inst (
      .crc_i         (crc_i),
      .data_i        (data_i),
      .crc_by_bytes_o(crc_by_bytes),
      .crc_next_o    (crc_next_o)
  );

  always_comb begin
    crc_end = crc_by_bytes[end_pos_i[LAST_BYTES_W-1:0]];
    if (end_pos_i == POS_W'(PCS_PAYLOAD_BYTES)) begin
      crc_end = crc_next_o;
    end

    fcs           = ~crc_end;
    word_with_fcs = WIDE_W'(data_i) | (WIDE_W'(fcs) << {end_pos_i, 3'b000});
    fcs_fits_o    = end_pos_i < POS_W'(PCS_PAYLOAD_BYTES - FCS_BYTES);

    term_data    = word_with_fcs[TERM_D_W-1:0];
    term_bytes_o = LAST_BYTES_W'(end_pos_i + POS_W'(FCS_BYTES));
    if (!fcs_fits_o) begin
      term_data    = TERM_D_W'(word_with_fcs[WIDE_W-1:PCS_PAYLOAD_W]);
      term_bytes_o = LAST_BYTES_W'(end_pos_i - POS_W'(FCS_BYTES));
    end
  end

  assign data_block_o = word_with_fcs[PCS_PAYLOAD_W-1:0];
  assign term_block_o = {term_data, TERM_TYPES[term_bytes_o]};

endmodule
