module tx_fcs_encoder
  import pcs_pkg::*;
  import crc32_pkg::*;
  import pcs_pkg::BYTE_W;
(
  input  logic [CRC_W-1:0]         crc_i,
  input  logic [PCS_PAYLOAD_W-1:0] data_i,
  input  logic [LAST_BYTES_W:0]    end_pos_i,
  output logic [CRC_W-1:0]         crc_next_o,
  output logic [CRC_W-1:0]         fcs_o,
  output logic [LAST_BYTES_W-1:0]  term_bytes_o,
  output logic                     fcs_fits_o
);

  localparam int POS_W     = LAST_BYTES_W + 1;
  localparam int FCS_BYTES = CRC_W / BYTE_W;

  logic [CRC_W-1:0] crc_by_bytes [PCS_PAYLOAD_BYTES];
  logic [CRC_W-1:0] crc_end;

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

    fcs_o      = ~crc_end;
    fcs_fits_o = end_pos_i < POS_W'(PCS_PAYLOAD_BYTES - FCS_BYTES);

    term_bytes_o = LAST_BYTES_W'(end_pos_i + POS_W'(FCS_BYTES));
    if (!fcs_fits_o) begin
      term_bytes_o = LAST_BYTES_W'(end_pos_i - POS_W'(FCS_BYTES));
    end
  end

endmodule
