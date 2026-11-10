module ipv6_stage
  import parser_pkg::*;
  import pcs_pkg::BYTE_W;
(
  input  logic                clk,
  input  logic                rst,
         axi_stream_if.slave  s_axi,
  input  parse_meta_t         meta_i,
         axi_stream_if.master m_axi,
  output parse_meta_t         meta_o
);

  localparam int MASK_W = s_axi.MASK_W;

  logic                    accept;
  logic                    active;
  parse_meta_t             meta_next;

  logic [BYTE_W-1:0]       ver;
  logic                    ver_present;
  logic [IP_LEN_W-1:0]     payload_len;
  logic                    payload_len_present;
  logic [IP_PROTO_W-1:0]   next_hdr;
  logic                    next_hdr_present;

  logic [IP_VERSION_W-1:0] version;
  logic [OFF_W-1:0]        l4_off;
  logic                    fields_present;

  always_comb begin
    active = meta_i.eth_ok && meta_i.ethertype == ETHERTYPE_IPV6;
  end

  field_capture #(
      .BYTES (1),
      .MASK_W(MASK_W)
  ) ver_capture (
      .clk      (clk),
      .rst      (rst),
      .data_i   (s_axi.data),
      .mask_i   (s_axi.mask),
      .accept_i (accept),
      .last_i   (s_axi.last),
      .en_i     (active),
      .pos_i    (meta_i.pos),
      .off_i    (meta_i.payload_off + OFF_W'(IPV6_VER_OFF)),
      .field_o  (ver),
      .present_o(ver_present)
  );

  field_capture #(
      .BYTES (2),
      .MASK_W(MASK_W)
  ) payload_len_capture (
      .clk      (clk),
      .rst      (rst),
      .data_i   (s_axi.data),
      .mask_i   (s_axi.mask),
      .accept_i (accept),
      .last_i   (s_axi.last),
      .en_i     (active),
      .pos_i    (meta_i.pos),
      .off_i    (meta_i.payload_off + OFF_W'(IPV6_LEN_OFF)),
      .field_o  (payload_len),
      .present_o(payload_len_present)
  );

  field_capture #(
      .BYTES (1),
      .MASK_W(MASK_W)
  ) next_hdr_capture (
      .clk      (clk),
      .rst      (rst),
      .data_i   (s_axi.data),
      .mask_i   (s_axi.mask),
      .accept_i (accept),
      .last_i   (s_axi.last),
      .en_i     (active),
      .pos_i    (meta_i.pos),
      .off_i    (meta_i.payload_off + OFF_W'(IPV6_NH_OFF)),
      .field_o  (next_hdr),
      .present_o(next_hdr_present)
  );

  always_comb begin
    version        = ver[BYTE_W-1-:IP_VERSION_W];
    l4_off         = meta_i.payload_off + OFF_W'(IPV6_HDR_BYTES);
    fields_present = ver_present && payload_len_present && next_hdr_present;

    meta_next      = meta_i;
    if (active) begin
      meta_next.ip_ok    = fields_present && version == IP_VERSION_W'(IPV6_VERSION) && payload_len != '0;
      meta_next.ip_v6    = 1'b1;
      meta_next.addr_off = meta_i.payload_off + OFF_W'(IPV6_ADDR_OFF);
      meta_next.l4_known = fields_present;
      meta_next.l4_proto = next_hdr;
      meta_next.l4_off   = l4_off;
      meta_next.l4_end   = l4_off + OFF_W'(payload_len);
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
