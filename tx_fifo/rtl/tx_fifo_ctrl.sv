module tx_fifo_ctrl #(
  parameter int FIFO_DEPTH = 64
) (
  input  logic                   s_clk,
  input  logic                   s_rst,
  input  logic                   m_clk,
  input  logic                   m_rst,
         axi_stream_if.slave     s_axi,
         tx_eth_stream_if.master tx_stream_o
);

  localparam int INPUT_SCALE    = s_axi.DATA_W / tx_stream_o.DATA_W;
  localparam int LANE_COUNT_W   = $clog2(INPUT_SCALE);
  localparam int S_COUNT_W      = $clog2(s_axi.MASK_W + 1);
  localparam int S_LAST_BYTES_W = $clog2(s_axi.MASK_W);

  if (s_axi.DATA_W % tx_stream_o.DATA_W != 0 || INPUT_SCALE < 2
      || (INPUT_SCALE & (INPUT_SCALE - 1)) != 0) begin : g_width_check
    $error("s_axi.DATA_W (%0d) must be a power-of-two multiple (>= 2) of tx_stream_o.DATA_W (%0d)",
           s_axi.DATA_W, tx_stream_o.DATA_W);
  end

  function automatic logic [S_COUNT_W-1:0] count_bytes(input logic [s_axi.MASK_W-1:0] mask);
    count_bytes = '0;
    for (int i = 0; i < s_axi.MASK_W; i++) begin
      count_bytes = count_bytes + S_COUNT_W'(mask[i]);
    end
  endfunction

  logic                      tail_d;
  logic                      tail_q;

  logic [LANE_COUNT_W-1:0]   lane_counter_d;
  logic [LANE_COUNT_W-1:0]   lane_counter_q;

  logic [S_COUNT_W-1:0]      row_bytes;
  logic                      full_last;
  logic                      accept;
  logic [S_LAST_BYTES_W-1:0] row_last_bytes;

  logic                      wr_fifo;
  logic                      commit_data;
  logic                      fifo_full;

  logic [s_axi.DATA_W-1:0]   fifo_data;
  logic [S_LAST_BYTES_W-1:0] fifo_last_bytes;
  logic                      fifo_last;
  logic                      fifo_valid;
  logic                      fifo_ready;

  logic [LANE_COUNT_W-1:0]   last_lane;
  logic                      at_last_lane;

  always_comb begin
    row_bytes   = count_bytes(s_axi.mask);
    full_last   = s_axi.last && row_bytes == S_COUNT_W'(s_axi.MASK_W);
    accept      = s_axi.valid && s_axi.ready;

    wr_fifo     = accept || tail_q;
    commit_data = tail_q || (s_axi.last && !full_last);
  end

  always_comb begin
    tail_d         = tail_q;
    row_last_bytes = S_LAST_BYTES_W'(row_bytes);

    if (accept && full_last) begin
      tail_d = 1'b1;
    end

    if (tail_q) begin
      row_last_bytes = '0;
      if (!fifo_full) begin
        tail_d = 1'b0;
      end
    end
  end

  always_ff @(posedge s_clk) begin
    if (s_rst) begin
      tail_q <= 1'b0;
    end else begin
      tail_q <= tail_d;
    end
  end

  async_packet_fifo #(
      .DATA_W    (s_axi.DATA_W),
      .FIFO_DEPTH(FIFO_DEPTH)
  ) async_packet_fifo_inst (
      .s_clk       (s_clk),
      .s_rst       (s_rst),
      .m_clk       (m_clk),
      .m_rst       (m_rst),
      .data_i      (s_axi.data),
      .last_bytes_i(row_last_bytes),
      .valid_i     (wr_fifo),
      .commit_i    (commit_data),
      .revert_i    (1'b0),
      .full_o      (fifo_full),
      .data_o      (fifo_data),
      .last_bytes_o(fifo_last_bytes),
      .last_o      (fifo_last),
      .valid_o     (fifo_valid),
      .ready_i     (fifo_ready)
  );

  always_comb begin
    last_lane = '1;
    if (fifo_last) begin
      last_lane = LANE_COUNT_W'(fifo_last_bytes >> tx_stream_o.LAST_BYTES_W);
    end

    at_last_lane = lane_counter_q == last_lane;
    fifo_ready   = tx_stream_o.ready && at_last_lane;
  end

  always_comb begin
    lane_counter_d = lane_counter_q;

    if (fifo_valid && tx_stream_o.ready) begin
      lane_counter_d = lane_counter_q + 1;
      if (at_last_lane) begin
        lane_counter_d = '0;
      end
    end
  end

  always_ff @(posedge m_clk) begin
    if (m_rst) begin
      lane_counter_q <= '0;
    end else begin
      lane_counter_q <= lane_counter_d;
    end
  end

  assign s_axi.ready = !s_rst && !fifo_full && !tail_q;

  always_comb begin
    tx_stream_o.data       = fifo_data[lane_counter_q*tx_stream_o.DATA_W +: tx_stream_o.DATA_W];
    tx_stream_o.last_bytes = tx_stream_o.LAST_BYTES_W'(fifo_last_bytes);
    tx_stream_o.valid      = fifo_valid;
    tx_stream_o.last       = fifo_last && at_last_lane;
  end

endmodule
