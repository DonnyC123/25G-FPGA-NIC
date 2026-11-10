module ipv4_opt_stage
  import parser_pkg::*;
  import pcs_pkg::BYTE_W;
#(
  parameter int FINAL = 0
) (
  input  logic                clk,
  input  logic                rst,
         axi_stream_if.slave  s_axi,
  input  parse_meta_t         meta_i,
         axi_stream_if.master m_axi,
  output parse_meta_t         meta_o
);

  localparam int MASK_W = s_axi.MASK_W;
  localparam int NOP_W  = $clog2(OPT_NOP_RUN + 1);

  logic                              accept;
  logic                              active;
  parse_meta_t                       meta_next;

  logic [OPT_WINDOW-1:0][BYTE_W-1:0] win;
  logic [OPT_WINDOW-1:0]             win_present;

  logic [NOP_W-1:0]                  nops;
  logic [OFF_W-1:0]                  start;
  logic [BYTE_W-1:0]                 opt_type;
  logic [BYTE_W-1:0]                 opt_len;
  logic [BYTE_W-1:0]                 opt_ptr;
  logic                              type_present;
  logic                              ptr_present;
  logic                              is_srr;
  logic [OFF_W-1:0]                  next_off;
  logic                              bad;

  always_comb begin
    active = meta_i.eth_ok && meta_i.ethertype == ETHERTYPE_IPV4 && meta_i.ip_ok && !meta_i.ip_v6 &&
             meta_i.l4_known && !meta_i.opt_done;
  end

  for (genvar k = 0; k < OPT_WINDOW; k++) begin : g_win
    field_capture #(
        .BYTES (1),
        .MASK_W(MASK_W)
    ) win_capture (
        .clk      (clk),
        .rst      (rst),
        .data_i   (s_axi.data),
        .mask_i   (s_axi.mask),
        .accept_i (accept),
        .last_i   (s_axi.last),
        .en_i     (active),
        .pos_i    (meta_i.pos),
        .off_i    (meta_i.opt_off + OFF_W'(k)),
        .field_o  (win[k]),
        .present_o(win_present[k])
    );
  end

  always_comb begin
    nops = '0;
    for (int k = 0; k < OPT_NOP_RUN; k++) begin
      if (nops == NOP_W'(k) && win_present[k] && win[k] == IPV4_OPT_NOP) begin
        nops = NOP_W'(k + 1);
      end
    end

    opt_type     = '0;
    opt_len      = '0;
    opt_ptr      = '0;
    type_present = 1'b0;
    ptr_present  = 1'b0;
    for (int k = 0; k < OPT_NOP_RUN; k++) begin
      if (nops == NOP_W'(k)) begin
        opt_type     = win[k];
        opt_len      = win[k+1];
        opt_ptr      = win[k+2];
        type_present = win_present[k] && win_present[k+1];
        ptr_present  = win_present[k+2];
      end
    end

    start    = meta_i.opt_off + OFF_W'(nops);
    is_srr   = opt_type == IPV4_OPT_LSRR || opt_type == IPV4_OPT_SSRR;
    next_off = start + OFF_W'(opt_len);
    bad      = opt_len < BYTE_W'(OPT_MIN_LEN) || next_off > meta_i.l4_off ||
               (is_srr && (opt_len < BYTE_W'(OPT_SRR_MIN_LEN) || meta_i.dst_alt));

    meta_next = meta_i;
    if (active) begin
      if (start >= meta_i.l4_off) begin
        meta_next.opt_done = 1'b1;
      end else if (nops == NOP_W'(OPT_NOP_RUN)) begin
        meta_next.opt_off = start;
      end else if (!type_present) begin
        meta_next.opt_done  = 1'b1;
        meta_next.csum_skip = 1'b1;
      end else if (opt_type == IPV4_OPT_EOL) begin
        meta_next.opt_done = 1'b1;
      end else if (bad || (is_srr && !ptr_present)) begin
        meta_next.opt_done  = 1'b1;
        meta_next.csum_skip = 1'b1;
      end else begin
        meta_next.opt_off  = next_off;
        meta_next.opt_done = next_off == meta_i.l4_off;
        if (is_srr && opt_ptr <= opt_len) begin
          meta_next.dst_alt     = 1'b1;
          meta_next.dst_alt_off = next_off - OFF_W'(IPV4_ADDR_LEN);
        end
      end

      if (FINAL != 0 && !meta_next.opt_done) begin
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
