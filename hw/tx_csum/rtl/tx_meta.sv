module tx_meta
  import tx_meta_pkg::*;
  import pcs_pkg::BYTE_W;
(
  input  logic                                    clk,
  input  logic                                    rst,
         axi_stream_if.slave                      s_axi,
         axi_stream_if.master                     m_axi,
  output tx_meta_t                                meta_o,
  output logic                [TX_META_BYTES-1:0] csum_mask_o
);

  localparam int DATA_W = s_axi.DATA_W;
  localparam int MASK_W = s_axi.MASK_W;
  localparam int LANE_W = $clog2(MASK_W + 1);

  if (MASK_W != TX_META_BYTES) begin : g_width_check
    $error("s_axi.MASK_W (%0d) must equal TX_META_BYTES (%0d)", MASK_W, TX_META_BYTES);
  end

  logic     [MASK_W-1:0][BYTE_W-1:0] data_in;
  logic                              advance;
  logic                              accept;

  logic                              first_d;
  logic                              first_q;
  tx_meta_t                          frame_meta_d;
  tx_meta_t                          frame_meta_q;
  logic     [TX_OFF_W-1:0]           pos_d;
  logic     [TX_OFF_W-1:0]           pos_q;
  logic     [TX_OFF_W-1:0]           start;
  logic     [LANE_W-1:0]             lo;
  logic     [MASK_W-1:0]             csum_range;

  logic     [DATA_W-1:0]             data_d;
  logic     [DATA_W-1:0]             data_q;
  logic     [MASK_W-1:0]             mask_d;
  logic     [MASK_W-1:0]             mask_q;
  logic                              last_d;
  logic                              last_q;
  logic                              valid_d;
  logic                              valid_q;
  tx_meta_t                          meta_d;
  tx_meta_t                          meta_q;
  logic     [MASK_W-1:0]             csum_mask_d;
  logic     [MASK_W-1:0]             csum_mask_q;

  always_comb begin
    data_in     = {>>{s_axi.data}};
    advance     = !valid_q || m_axi.ready;
    s_axi.ready = first_q || advance;
    accept      = s_axi.valid && s_axi.ready;

    start       = TX_OFF_W'(frame_meta_q.csum_start);
    lo          = start <= pos_q ? '0 : start >= pos_q + TX_OFF_W'(MASK_W) ? LANE_W'(MASK_W) : LANE_W'(start - pos_q);

    for (int b = 0; b < MASK_W; b++) begin
      csum_range[b] = LANE_W'(b) >= lo;
    end

    first_d      = first_q;
    frame_meta_d = frame_meta_q;
    pos_d        = pos_q;
    data_d       = data_q;
    mask_d       = mask_q;
    last_d       = last_q;
    valid_d      = valid_q;
    meta_d       = meta_q;
    csum_mask_d  = csum_mask_q;

    if (advance) begin
      valid_d = accept && !first_q;
    end

    if (accept) begin
      first_d = s_axi.last;
      if (first_q) begin
        frame_meta_d.csum        = data_in[TX_META_FLAGS_OFF][TX_META_CSUM_BIT];
        frame_meta_d.csum_start  = {data_in[TX_META_START_OFF+1], data_in[TX_META_START_OFF]};
        frame_meta_d.csum_offset = {data_in[TX_META_OFFSET_OFF+1], data_in[TX_META_OFFSET_OFF]};
        frame_meta_d.frame_len   = {data_in[TX_META_LEN_OFF+1], data_in[TX_META_LEN_OFF]};
      end else begin
        pos_d       = s_axi.last ? '0 : pos_q + TX_OFF_W'(MASK_W);
        data_d      = s_axi.data;
        mask_d      = s_axi.mask;
        last_d      = s_axi.last;
        meta_d      = frame_meta_q;
        csum_mask_d = s_axi.mask & csum_range;
      end
    end
  end

  always_ff @(posedge clk) begin
    if (rst) begin
      first_q      <= 1'b1;
      pos_q        <= '0;
      valid_q      <= 1'b0;
      frame_meta_q <= 'x;
      data_q       <= 'x;
      mask_q       <= 'x;
      last_q       <= 'x;
      meta_q       <= 'x;
      csum_mask_q  <= 'x;
    end else begin
      first_q      <= first_d;
      pos_q        <= pos_d;
      valid_q      <= valid_d;
      frame_meta_q <= frame_meta_d;
      data_q       <= data_d;
      mask_q       <= mask_d;
      last_q       <= last_d;
      meta_q       <= meta_d;
      csum_mask_q  <= csum_mask_d;
    end
  end

  always_comb begin
    m_axi.data  = data_q;
    m_axi.mask  = mask_q;
    m_axi.last  = last_q;
    m_axi.valid = valid_q;
    meta_o      = meta_q;
    csum_mask_o = csum_mask_q;
  end

endmodule
