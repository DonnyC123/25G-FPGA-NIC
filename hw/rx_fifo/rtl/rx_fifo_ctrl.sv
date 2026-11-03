module rx_fifo_ctrl
  import pcs_pkg::*;
#(
  parameter int FIFO_DEPTH = 64
) (
  input  logic                s_clk,
  input  logic                s_rst,
  input  logic                m_clk,
  input  logic                m_rst,
  input  rx_eth_stream_t      eth_stream_i,
  output logic                cancel_o,
         axi_stream_if.master m_axi
);

  localparam int OUTPUT_SCALE   = m_axi.DATA_W / ETH_DATA_W;
  localparam int M_LAST_BYTES_W = $clog2(m_axi.MASK_W);

  if (m_axi.DATA_W % ETH_DATA_W != 0 || OUTPUT_SCALE < 2 || (OUTPUT_SCALE & (OUTPUT_SCALE - 1)) != 0) begin : g_width_check
    $error("m_axi.DATA_W (%0d) must be a power-of-two multiple (>= 2) of ETH_DATA_W (%0d)",
           m_axi.DATA_W, ETH_DATA_W);
  end

  function automatic logic [m_axi.MASK_W-1:0] last_mask(input logic [M_LAST_BYTES_W-1:0] last_bytes);
    for (int i = 0; i < m_axi.MASK_W; i++) begin
      last_mask[i] = M_LAST_BYTES_W'(i) < last_bytes;
    end
  endfunction

  logic                      commit_data;
  logic                      revert_data;
  logic                      fifo_full;

  logic [M_LAST_BYTES_W-1:0] fifo_last_bytes;
  logic                      fifo_last;

  always_comb begin
    commit_data = eth_stream_i.valid && eth_stream_i.last;
    revert_data = eth_stream_i.drop || (eth_stream_i.valid && fifo_full);
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
      .data_o      (m_axi.data),
      .last_bytes_o(fifo_last_bytes),
      .last_o      (fifo_last),
      .valid_o     (m_axi.valid),
      .ready_i     (m_axi.ready)
  );

  assign cancel_o = revert_data;

  always_comb begin
    m_axi.last = fifo_last;
    m_axi.mask = '1;
    if (fifo_last) begin
      m_axi.mask = last_mask(fifo_last_bytes);
    end
  end

endmodule
