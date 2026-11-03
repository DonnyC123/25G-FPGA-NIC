module crc_checker
  import pcs_pkg::*;
  import crc32_pkg::*;
  import pcs_pkg::BYTE_W;
(
  input  logic           clk,
  input  logic           rst,
  input  rx_eth_stream_t eth_stream_i,
  output logic           drop_o
);

  logic [CRC_W-1:0] crc_d;
  logic [CRC_W-1:0] crc_q;

  logic [CRC_W-1:0] crc_by_bytes [ETH_DATA_BYTES];
  logic [CRC_W-1:0] crc_next;
  logic             crc_ok;
  logic             frame_end;

  crc32_word #(
      .BYTES(ETH_DATA_BYTES)
  ) crc32_word_inst (
      .crc_i         (crc_q),
      .data_i        (eth_stream_i.data),
      .crc_by_bytes_o(crc_by_bytes),
      .crc_next_o    (crc_next)
  );

  always_comb begin
    crc_ok    = crc_by_bytes[eth_stream_i.last_bytes] == CRC32_RESIDUE;
    frame_end = eth_stream_i.valid && eth_stream_i.last;
  end

  always_comb begin
    crc_d = crc_q;

    if (eth_stream_i.valid) begin
      crc_d = crc_next;
    end

    if (frame_end || eth_stream_i.drop) begin
      crc_d = CRC_INIT;
    end
  end

  always_ff @(posedge clk) begin
    if (rst) begin
      crc_q <= CRC_INIT;
    end else begin
      crc_q <= crc_d;
    end
  end

  assign drop_o = frame_end && !crc_ok;

endmodule
