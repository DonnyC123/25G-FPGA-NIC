module ipv4_stage
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

  logic [BYTE_W-1:0]       ver_ihl;
  logic                    ver_ihl_present;
  logic [IP_LEN_W-1:0]     total_len;
  logic                    total_len_present;
  logic [IP_LEN_W-1:0]     frag;
  logic                    frag_present;
  logic [IP_PROTO_W-1:0]   proto;
  logic                    proto_present;

  logic [IP_VERSION_W-1:0] version;
  logic [IP_VERSION_W-1:0] ihl;
  logic [OFF_W-1:0]        hdr_bytes;
  logic                    fields_present;

  always_comb begin
    active = meta_i.eth_ok && meta_i.ethertype == ETHERTYPE_IPV4;
  end

  field_capture #(
      .BYTES (1),
      .MASK_W(MASK_W)
  ) ver_ihl_capture (
      .clk      (clk),
      .rst      (rst),
      .data_i   (s_axi.data),
      .mask_i   (s_axi.mask),
      .accept_i (accept),
      .last_i   (s_axi.last),
      .en_i     (active),
      .pos_i    (meta_i.pos),
      .off_i    (meta_i.payload_off + OFF_W'(IPV4_VER_IHL_OFF)),
      .field_o  (ver_ihl),
      .present_o(ver_ihl_present)
  );

  field_capture #(
      .BYTES (2),
      .MASK_W(MASK_W)
  ) total_len_capture (
      .clk      (clk),
      .rst      (rst),
      .data_i   (s_axi.data),
      .mask_i   (s_axi.mask),
      .accept_i (accept),
      .last_i   (s_axi.last),
      .en_i     (active),
      .pos_i    (meta_i.pos),
      .off_i    (meta_i.payload_off + OFF_W'(IPV4_LEN_OFF)),
      .field_o  (total_len),
      .present_o(total_len_present)
  );

  field_capture #(
      .BYTES (2),
      .MASK_W(MASK_W)
  ) frag_capture (
      .clk      (clk),
      .rst      (rst),
      .data_i   (s_axi.data),
      .mask_i   (s_axi.mask),
      .accept_i (accept),
      .last_i   (s_axi.last),
      .en_i     (active),
      .pos_i    (meta_i.pos),
      .off_i    (meta_i.payload_off + OFF_W'(IPV4_FRAG_OFF)),
      .field_o  (frag),
      .present_o(frag_present)
  );

  field_capture #(
      .BYTES (1),
      .MASK_W(MASK_W)
  ) proto_capture (
      .clk      (clk),
      .rst      (rst),
      .data_i   (s_axi.data),
      .mask_i   (s_axi.mask),
      .accept_i (accept),
      .last_i   (s_axi.last),
      .en_i     (active),
      .pos_i    (meta_i.pos),
      .off_i    (meta_i.payload_off + OFF_W'(IPV4_PROTO_OFF)),
      .field_o  (proto),
      .present_o(proto_present)
  );

  always_comb begin
    version        = ver_ihl[BYTE_W-1-:IP_VERSION_W];
    ihl            = ver_ihl[IP_VERSION_W-1:0];
    hdr_bytes      = OFF_W'(ihl) << IPV4_IHL_SHIFT;
    fields_present = ver_ihl_present && total_len_present && frag_present && proto_present;

    meta_next      = meta_i;
    if (active) begin
      meta_next.ip_ok     = fields_present && version == IP_VERSION_W'(IPV4_VERSION) &&
                            ihl >= IP_VERSION_W'(IPV4_MIN_IHL) && OFF_W'(total_len) >= hdr_bytes &&
                            (frag & IPV4_FRAG_MASK) == '0;
      meta_next.ip_v6     = 1'b0;
      meta_next.csum_skip = ihl != IP_VERSION_W'(IPV4_MIN_IHL);
      meta_next.addr_off  = meta_i.payload_off + OFF_W'(IPV4_ADDR_OFF);
      meta_next.l4_known  = fields_present;
      meta_next.l4_proto  = proto;
      meta_next.l4_off    = meta_i.payload_off + hdr_bytes;
      meta_next.l4_end    = meta_i.payload_off + OFF_W'(total_len);
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
