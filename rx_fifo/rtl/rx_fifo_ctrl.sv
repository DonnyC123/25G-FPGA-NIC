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
  localparam int BUFF_COUNT_W   = $clog2(OUTPUT_SCALE);
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

  logic [m_axi.DATA_W-1:0]   data_buff_d;
  logic [m_axi.DATA_W-1:0]   data_buff_q;

  logic [BUFF_COUNT_W-1:0]   buff_counter_d;
  logic [BUFF_COUNT_W-1:0]   buff_counter_q;

  logic                      row_done;
  logic [BUFF_COUNT_W-1:0]   empty_words;
  logic [m_axi.DATA_W-1:0]   row_data;
  logic [M_LAST_BYTES_W-1:0] row_last_bytes;

  logic                      wr_fifo;
  logic                      commit_data;
  logic                      revert_data;
  logic                      fifo_full;

  logic [M_LAST_BYTES_W-1:0] fifo_last_bytes;
  logic                      fifo_last;

  always_comb begin
    row_done    = eth_stream_i.valid && (eth_stream_i.last || buff_counter_q == '1);

    wr_fifo     = row_done;
    commit_data = eth_stream_i.valid && eth_stream_i.last;
    revert_data = eth_stream_i.drop || (row_done && fifo_full);
  end

  always_comb begin
    buff_counter_d = buff_counter_q;
    data_buff_d    = data_buff_q;

    if (eth_stream_i.valid) begin
      buff_counter_d = buff_counter_q + 1;
      data_buff_d    = {eth_stream_i.data, data_buff_q[m_axi.DATA_W-1:ETH_DATA_W]};
    end

    if (row_done || revert_data) begin
      buff_counter_d = '0;
    end
  end

  always_comb begin
    empty_words    = ~buff_counter_q;
    row_data       = data_buff_d >> (ETH_DATA_W * empty_words);
    row_last_bytes = {buff_counter_q, eth_stream_i.last_bytes};
  end

  always_ff @(posedge s_clk) begin
    if (s_rst) begin
      buff_counter_q <= '0;
    end else begin
      buff_counter_q <= buff_counter_d;
    end
  end

  always_ff @(posedge s_clk) begin
    data_buff_q <= data_buff_d;
  end

  async_packet_fifo #(
      .DATA_W    (m_axi.DATA_W),
      .FIFO_DEPTH(FIFO_DEPTH)
  ) async_packet_fifo_inst (
      .s_clk       (s_clk),
      .s_rst       (s_rst),
      .m_clk       (m_clk),
      .m_rst       (m_rst),
      .data_i      (row_data),
      .last_bytes_i(row_last_bytes),
      .valid_i     (wr_fifo),
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
