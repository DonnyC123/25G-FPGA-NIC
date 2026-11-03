module crc32_word
  import crc32_pkg::*;
#(
  parameter int BYTES = 8
) (
  input  logic [CRC_W-1:0]        crc_i,
  input  logic [BYTES*BYTE_W-1:0] data_i,
  output logic [CRC_W-1:0]        crc_by_bytes_o [BYTES],
  output logic [CRC_W-1:0]        crc_next_o
);

  always_comb begin
    crc_by_bytes_o[0] = crc_i;
    for (int b = 0; b < BYTES - 1; b++) begin
      crc_by_bytes_o[b+1] = crc32_byte(crc_by_bytes_o[b], data_i[b*BYTE_W +: BYTE_W]);
    end

    crc_next_o = crc32_byte(crc_by_bytes_o[BYTES-1], data_i[(BYTES-1)*BYTE_W +: BYTE_W]);
  end

endmodule
