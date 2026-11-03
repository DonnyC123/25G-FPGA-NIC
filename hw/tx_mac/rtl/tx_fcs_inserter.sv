module tx_fcs_inserter
  import pcs_pkg::*;
  import crc32_pkg::*;
  import pcs_pkg::BYTE_W;
(
  input  logic [PCS_PAYLOAD_W-1:0] data_i,
  input  logic [CRC_W-1:0]         fcs_i,
  input  logic [LAST_BYTES_W:0]    end_pos_i,
  input  logic [LAST_BYTES_W-1:0]  term_bytes_i,
  input  logic                     fcs_fits_i,
  output logic [PCS_PAYLOAD_W-1:0] data_block_o,
  output logic [PCS_PAYLOAD_W-1:0] term_block_o
);

  localparam int WIDE_W   = PCS_PAYLOAD_W + CRC_W;
  localparam int TERM_D_W = PCS_PAYLOAD_W - BYTE_W;

  logic [WIDE_W-1:0]   word_with_fcs;
  logic [TERM_D_W-1:0] term_data;

  always_comb begin
    word_with_fcs = WIDE_W'(data_i) | (WIDE_W'(fcs_i) << {end_pos_i, 3'b000});

    term_data = word_with_fcs[TERM_D_W-1:0];
    if (!fcs_fits_i) begin
      term_data = TERM_D_W'(word_with_fcs[WIDE_W-1:PCS_PAYLOAD_W]);
    end
  end

  assign data_block_o = word_with_fcs[PCS_PAYLOAD_W-1:0];
  assign term_block_o = {term_data, TERM_TYPES[term_bytes_i]};

endmodule
