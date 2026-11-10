module udp_stage
  import parser_pkg::*;
(
  input  logic                clk,
  input  logic                rst,
         axi_stream_if.slave  s_axi,
  input  parse_meta_t         meta_i,
         axi_stream_if.master m_axi,
  output parse_meta_t         meta_o
);

  localparam int MASK_W = s_axi.MASK_W;

  logic                accept;
  logic                active;
  parse_meta_t         meta_next;

  logic [IP_LEN_W-1:0] udp_len;
  logic                udp_len_present;
  logic [OFF_W-1:0]    ip_payload_len;

  always_comb begin
    active = meta_i.ip_ok && meta_i.l4_known && meta_i.l4_proto == IP_PROTO_UDP;
  end

  field_capture #(
      .BYTES (2),
      .MASK_W(MASK_W)
  ) udp_len_capture (
      .clk      (clk),
      .rst      (rst),
      .data_i   (s_axi.data),
      .mask_i   (s_axi.mask),
      .accept_i (accept),
      .last_i   (s_axi.last),
      .en_i     (active),
      .pos_i    (meta_i.pos),
      .off_i    (meta_i.l4_off + OFF_W'(UDP_LEN_OFF)),
      .field_o  (udp_len),
      .present_o(udp_len_present)
  );

  always_comb begin
    ip_payload_len   = meta_i.l4_end - meta_i.l4_off;

    meta_next        = meta_i;
    meta_next.udp_ok = active && udp_len_present && meta_i.l4_off + OFF_W'(UDP_HDR_BYTES) <= meta_i.l4_end &&
                       OFF_W'(udp_len) == ip_payload_len;
    if (active) begin
      meta_next.csum_pos = meta_i.l4_off + OFF_W'(UDP_CSUM_OFF);
    end
  end

  parse_reg parse_reg_inst (
      .clk     (clk),
      .rst     (rst),
      .s_axi   (s_axi),
      .meta_i  (meta_next),
      .accept_o(accept),
      .m_axi   (m_axi),
      .meta_o  (meta_o)
  );

endmodule
