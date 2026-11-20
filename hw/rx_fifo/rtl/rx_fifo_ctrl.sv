module rx_fifo_ctrl
  import pcs_pkg::*;
  import rx_meta_pkg::*;
#(
  parameter int FIFO_DEPTH = 64
) (
  input  logic                s_clk,
  input  logic                s_rst,
  input  logic                m_clk,
  input  logic                m_rst,
  input  rx_eth_stream_t      eth_stream_i,
  input  rx_meta_t            meta_i,
  output logic                cancel_o,
         axi_stream_if.master m_axi
);

  localparam int OUTPUT_SCALE    = m_axi.DATA_W / ETH_DATA_W;
  localparam int M_LAST_BYTES_W  = $clog2(m_axi.MASK_W);
  localparam int MIN_FRAME_ROWS  = ((ETH_MIN_FRAME_BYTES * BYTE_W) + m_axi.DATA_W - 1) / m_axi.DATA_W;
  localparam int META_FIFO_DEPTH = FIFO_DEPTH / MIN_FRAME_ROWS;

  if (m_axi.DATA_W % ETH_DATA_W != 0 || OUTPUT_SCALE < 2 || (OUTPUT_SCALE & (OUTPUT_SCALE - 1)) != 0) begin : g_width_check
    $error("m_axi.DATA_W (%0d) must be a power-of-two multiple (>= 2) of ETH_DATA_W (%0d)", m_axi.DATA_W, ETH_DATA_W);
  end

  if (m_axi.DATA_W != RX_META_BYTES * RX_META_BYTE_W) begin : g_meta_width_check
    $error("m_axi.DATA_W (%0d) must hold exactly one %0d-byte metadata beat", m_axi.DATA_W, RX_META_BYTES);
  end

  function automatic logic [m_axi.MASK_W-1:0] last_mask(input logic [M_LAST_BYTES_W-1:0] last_bytes);
    for (int i = 0; i < m_axi.MASK_W; i++) begin
      last_mask[i] = M_LAST_BYTES_W'(i) < last_bytes;
    end
  endfunction

  logic                          commit_data;
  logic                          revert_data;
  logic                          meta_push;
  logic                          meta_ready;
  logic                          fifo_full;

  logic     [m_axi.DATA_W-1:0]   fifo_data;
  logic     [M_LAST_BYTES_W-1:0] fifo_last_bytes;
  logic                          fifo_last;
  logic                          fifo_valid;
  logic                          fifo_ready;

  rx_meta_t                      fifo_meta;
  logic                          fifo_meta_valid;
  logic                          fifo_meta_ready;

  rx_meta_t                      out_meta;
  logic                          out_meta_valid;
  logic                          out_meta_ready;

  logic                          send_meta_d;
  logic                          send_meta_q;

  always_comb begin
    commit_data = eth_stream_i.valid && eth_stream_i.last;
    revert_data = eth_stream_i.drop || (eth_stream_i.valid && fifo_full) || (commit_data && !meta_ready);
    meta_push   = commit_data && !revert_data;
  end

  async_packet_fifo #(
      .WR_DATA_W (ETH_DATA_W),
      .RD_DATA_W (m_axi.DATA_W),
      .FIFO_DEPTH(FIFO_DEPTH)
  ) async_packet_fifo_inst (
      .wr_clk      (s_clk),
      .wr_rst      (s_rst),
      .rd_clk      (m_clk),
      .rd_rst      (m_rst),
      .data_i      (eth_stream_i.data),
      .last_bytes_i(eth_stream_i.last_bytes),
      .valid_i     (eth_stream_i.valid),
      .commit_i    (commit_data),
      .revert_i    (revert_data),
      .full_o      (fifo_full),
      .data_o      (fifo_data),
      .last_bytes_o(fifo_last_bytes),
      .last_o      (fifo_last),
      .valid_o     (fifo_valid),
      .ready_i     (fifo_ready)
  );

  async_fifo #(
      .DATA_W    ($bits(rx_meta_t)),
      .FIFO_DEPTH(META_FIFO_DEPTH)
  ) meta_fifo_inst (
      .wr_clk (s_clk),
      .wr_rst (s_rst),
      .rd_clk (m_clk),
      .rd_rst (m_rst),
      .data_i (meta_i),
      .valid_i(meta_push),
      .ready_o(meta_ready),
      .data_o (fifo_meta),
      .valid_o(fifo_meta_valid),
      .ready_i(fifo_meta_ready)
  );

  skid_buffer #(
      .DATA_W($bits(rx_meta_t))
  ) meta_skid_inst (
      .clk    (m_clk),
      .rst    (m_rst),
      .data_i (fifo_meta),
      .valid_i(fifo_meta_valid),
      .ready_o(fifo_meta_ready),
      .data_o (out_meta),
      .valid_o(out_meta_valid),
      .ready_i(out_meta_ready)
  );

  assign cancel_o = revert_data;

  always_comb begin
    send_meta_d    = send_meta_q;
    out_meta_ready = 1'b0;
    fifo_ready     = 1'b0;

    m_axi.data     = fifo_data;
    m_axi.valid    = fifo_valid;
    m_axi.last     = fifo_last;
    m_axi.mask     = '1;
    if (fifo_last) begin
      m_axi.mask = last_mask(fifo_last_bytes);
    end

    if (send_meta_q) begin
      m_axi.data     = rx_meta_beat(out_meta);
      m_axi.valid    = out_meta_valid;
      m_axi.last     = 1'b0;
      m_axi.mask     = '1;
      out_meta_ready = m_axi.ready;
      if (out_meta_valid && m_axi.ready) begin
        send_meta_d = 1'b0;
      end
    end else begin
      fifo_ready = m_axi.ready;
      if (fifo_valid && m_axi.ready && fifo_last) begin
        send_meta_d = 1'b1;
      end
    end
  end

  always_ff @(posedge m_clk) begin
    if (m_rst) begin
      send_meta_q <= 1'b1;
    end else begin
      send_meta_q <= send_meta_d;
    end
  end

endmodule
