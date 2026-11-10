module eth_stage
  import parser_pkg::*;
  import pcs_pkg::BYTE_W;
(
  input  logic                clk,
  input  logic                rst,
         axi_stream_if.slave  s_axi,
         axi_stream_if.master m_axi,
  output parse_meta_t         meta_o
);

  localparam int MASK_W = s_axi.MASK_W;

  if (MASK_W < ETH_HDR_MAX) begin : g_width_check
    $error("s_axi.MASK_W (%0d) must be at least ETH_HDR_MAX (%0d)", MASK_W, ETH_HDR_MAX);
  end

  function automatic logic is_tag(input logic [ETHERTYPE_W-1:0] value);
    return value == ETHERTYPE_VLAN || value == ETHERTYPE_QINQ;
  endfunction

  logic                                first_d;
  logic                                first_q;
  logic [OFF_W-1:0]                    in_pos_d;
  logic [OFF_W-1:0]                    in_pos_q;

  logic                                accept;
  parse_meta_t                         meta_next;

  logic [MAX_VLANS:0][ETHERTYPE_W-1:0] type_fields;
  logic [MAX_VLANS:0]                  type_present;
  logic [VLAN_COUNT_W-1:0]             vlan_count;
  logic [ETHERTYPE_W-1:0]              ethertype;
  logic                                ethertype_present;
  logic                                eth_ok;
  logic [OFF_W-1:0]                    payload_off;

  always_comb begin
    for (int v = 0; v <= MAX_VLANS; v++) begin
      type_fields[v]  = {s_axi.data[(ETH_TYPE_OFF+VLAN_TAG_BYTES*v)*BYTE_W+:BYTE_W],
                         s_axi.data[(ETH_TYPE_OFF+VLAN_TAG_BYTES*v+1)*BYTE_W+:BYTE_W]};
      type_present[v] = s_axi.mask[ETH_TYPE_OFF+VLAN_TAG_BYTES*v+1];
    end

    vlan_count = '0;
    for (int v = 0; v < MAX_VLANS; v++) begin
      if (vlan_count == VLAN_COUNT_W'(v) && type_present[v] && is_tag(type_fields[v])) begin
        vlan_count = VLAN_COUNT_W'(v + 1);
      end
    end

    ethertype         = type_fields[0];
    ethertype_present = type_present[0];
    for (int v = 1; v <= MAX_VLANS; v++) begin
      if (vlan_count == VLAN_COUNT_W'(v)) begin
        ethertype         = type_fields[v];
        ethertype_present = type_present[v];
      end
    end

    eth_ok      = ethertype_present && !is_tag(ethertype) && ethertype >= ETHERTYPE_MIN;
    payload_off = OFF_W'(ETH_TYPE_OFF + ETHERTYPE_BYTES) + OFF_W'(VLAN_TAG_BYTES) * OFF_W'(vlan_count);
  end

  always_comb begin
    meta_next     = meta_o;
    meta_next.pos = in_pos_q;
    if (first_q) begin
      meta_next             = '0;
      meta_next.pos         = in_pos_q;
      meta_next.eth_ok      = eth_ok;
      meta_next.ethertype   = ethertype;
      meta_next.vlan_count  = vlan_count;
      meta_next.payload_off = payload_off;
    end

    first_d  = first_q;
    in_pos_d = in_pos_q;
    if (accept) begin
      first_d  = s_axi.last;
      in_pos_d = s_axi.last ? '0 : in_pos_q + OFF_W'(MASK_W);
    end
  end

  always_ff @(posedge clk) begin
    if (rst) begin
      first_q  <= 1'b1;
      in_pos_q <= '0;
    end else begin
      first_q  <= first_d;
      in_pos_q <= in_pos_d;
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
