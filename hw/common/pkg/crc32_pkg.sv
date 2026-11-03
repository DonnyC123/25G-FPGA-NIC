package crc32_pkg;

  localparam int CRC_W  = 32;
  localparam int BYTE_W = 8;

  localparam logic [CRC_W-1:0] CRC32_POLY_REFLECTED = 32'hEDB88320;
  localparam logic [CRC_W-1:0] CRC32_RESIDUE        = 32'hDEBB20E3;
  localparam logic [CRC_W-1:0] CRC_INIT             = 32'hFFFFFFFF;

  function automatic logic [CRC_W-1:0] crc32_byte(input logic [CRC_W-1:0]  crc_in,
                                                  input logic [BYTE_W-1:0] byte_in);
    crc32_byte = crc_in;
    for (int i = 0; i < BYTE_W; i++) begin
      if (crc32_byte[0] ^ byte_in[i]) begin
        crc32_byte = (crc32_byte >> 1) ^ CRC32_POLY_REFLECTED;
      end else begin
        crc32_byte = crc32_byte >> 1;
      end
    end
  endfunction

endpackage
