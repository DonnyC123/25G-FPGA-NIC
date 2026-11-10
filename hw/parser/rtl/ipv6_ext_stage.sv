module ipv6_ext_stage
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

  function automatic logic is_ext(input logic [IP_PROTO_W-1:0] proto);
    return proto == IP_PROTO_HOPOPT || proto == IP_PROTO_ROUTING || proto == IP_PROTO_FRAGMENT ||
           proto == IP_PROTO_AH || proto == IP_PROTO_DSTOPTS;
  endfunction

  logic                  accept;
  logic                  active;
  parse_meta_t           meta_next;

  logic [IP_PROTO_W-1:0] next_hdr;
  logic                  next_hdr_present;
  logic [BYTE_W-1:0]     ext_len;
  logic                  ext_len_present;
  logic [IP_LEN_W-1:0]   frag;
  logic                  frag_present;

  logic                  is_frag;
  logic                  known;
  logic                  frag_ok;
  logic [OFF_W-1:0]      ext_bytes;
  logic [OFF_W-1:0]      next_off;

  always_comb begin
    active = meta_i.ip_ok && meta_i.ip_v6 && meta_i.l4_known && is_ext(meta_i.l4_proto);
  end

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
      .off_i    (meta_i.l4_off + OFF_W'(IPV6_EXT_NH_OFF)),
      .field_o  (next_hdr),
      .present_o(next_hdr_present)
  );

  field_capture #(
      .BYTES (1),
      .MASK_W(MASK_W)
  ) ext_len_capture (
      .clk      (clk),
      .rst      (rst),
      .data_i   (s_axi.data),
      .mask_i   (s_axi.mask),
      .accept_i (accept),
      .last_i   (s_axi.last),
      .en_i     (active),
      .pos_i    (meta_i.pos),
      .off_i    (meta_i.l4_off + OFF_W'(IPV6_EXT_LEN_OFF)),
      .field_o  (ext_len),
      .present_o(ext_len_present)
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
      .off_i    (meta_i.l4_off + OFF_W'(IPV6_FRAG_OFF)),
      .field_o  (frag),
      .present_o(frag_present)
  );

  always_comb begin
    is_frag = meta_i.l4_proto == IP_PROTO_FRAGMENT;
    known   = next_hdr_present && ext_len_present && (!is_frag || frag_present);
    frag_ok = !is_frag || (frag & IPV6_FRAG_MASK) == '0;

    unique case (meta_i.l4_proto)
      IP_PROTO_FRAGMENT: ext_bytes = OFF_W'(IPV6_FRAG_BYTES);
      IP_PROTO_AH:       ext_bytes = (OFF_W'(ext_len) + OFF_W'(2)) << IPV6_AH_SHIFT;
      default:           ext_bytes = (OFF_W'(ext_len) + OFF_W'(1)) << IPV6_EXT_SHIFT;
    endcase
    next_off  = meta_i.l4_off + ext_bytes;

    meta_next = meta_i;
    if (active) begin
      meta_next.ip_ok    = !known || (frag_ok && next_off <= meta_i.l4_end);
      meta_next.l4_known = known;
      meta_next.l4_proto = next_hdr;
      meta_next.l4_off   = next_off;
      if (meta_i.l4_proto == IP_PROTO_ROUTING) begin
        meta_next.csum_skip = 1'b1;
      end
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
