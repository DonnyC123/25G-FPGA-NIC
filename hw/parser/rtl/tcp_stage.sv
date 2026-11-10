module tcp_stage
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

  logic              accept;
  logic              active;
  parse_meta_t       meta_next;

  logic [BYTE_W-1:0] doff_byte;
  logic              doff_present;
  logic [3:0]        doff;
  logic [OFF_W-1:0]  hdr_end;

  always_comb begin
    active = meta_i.ip_ok && meta_i.l4_known && meta_i.l4_proto == IP_PROTO_TCP;
  end

  field_capture #(
      .BYTES (1),
      .MASK_W(MASK_W)
  ) doff_capture (
      .clk      (clk),
      .rst      (rst),
      .data_i   (s_axi.data),
      .mask_i   (s_axi.mask),
      .accept_i (accept),
      .last_i   (s_axi.last),
      .en_i     (active),
      .pos_i    (meta_i.pos),
      .off_i    (meta_i.l4_off + OFF_W'(TCP_DOFF_OFF)),
      .field_o  (doff_byte),
      .present_o(doff_present)
  );

  always_comb begin
    doff               = doff_byte[BYTE_W-1-:4];
    hdr_end            = meta_i.l4_off + (OFF_W'(doff) << TCP_DOFF_SHIFT);

    meta_next        = meta_i;
    meta_next.tcp_ok = active && doff_present && doff >= 4'(TCP_MIN_DOFF) && hdr_end <= meta_i.l4_end;
    if (active) begin
      meta_next.csum_pos = meta_i.l4_off + OFF_W'(TCP_CSUM_OFF);
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
