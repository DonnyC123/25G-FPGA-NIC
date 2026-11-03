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

  localparam int S_LAST_BYTES_W = $clog2(s_axi.MASK_W);
  localparam int FIFO_OUT_W     = tx_stream_o.DATA_W + tx_stream_o.LAST_BYTES_W + 1;

  logic                      tail_d;
  logic                      tail_q;

  logic                      accept;
  logic                      full_last;
  logic                      wr_fifo;
  logic                      commit_data;
  logic [S_LAST_BYTES_W-1:0] row_last_bytes;
  logic                      fifo_full;

  logic [FIFO_OUT_W-1:0]     fifo_out;
  logic                      fifo_valid;
  logic                      fifo_ready;

  always_comb begin
    accept         = s_axi.valid && s_axi.ready;
    full_last      = s_axi.last && &s_axi.mask;

    wr_fifo        = accept || tail_q;
    commit_data    = tail_q || (s_axi.last && !full_last);
    row_last_bytes = tail_q ? '0 : S_LAST_BYTES_W'($countones(s_axi.mask));

    tail_d         = tail_q ? fifo_full : accept && full_last;
  end

  always_ff @(posedge s_clk) begin
    if (s_rst) begin
      tail_q <= 1'b0;
    end else begin
      tail_q <= tail_d;
    end
  end

  assign s_axi.ready = !s_rst && !fifo_full && !tail_q;

  async_packet_fifo #(
      .WR_DATA_W (s_axi.DATA_W),
      .RD_DATA_W (tx_stream_o.DATA_W),
      .FIFO_DEPTH(FIFO_DEPTH)
  ) async_packet_fifo_inst (
      .wr_clk      (s_clk),
      .wr_rst      (s_rst),
      .rd_clk      (m_clk),
      .rd_rst      (m_rst),
      .data_i      (s_axi.data),
      .last_bytes_i(row_last_bytes),
      .valid_i     (wr_fifo),
      .commit_i    (commit_data),
      .revert_i    (1'b0),
      .full_o      (fifo_full),
      .data_o      (fifo_out[FIFO_OUT_W-1-:tx_stream_o.DATA_W]),
      .last_bytes_o(fifo_out[1+:tx_stream_o.LAST_BYTES_W]),
      .last_o      (fifo_out[0]),
      .valid_o     (fifo_valid),
      .ready_i     (fifo_ready)
  );

  skid_buffer #(
      .DATA_W(FIFO_OUT_W)
  ) skid_buffer_inst (
      .clk    (m_clk),
      .rst    (m_rst),
      .data_i (fifo_out),
      .valid_i(fifo_valid),
      .ready_o(fifo_ready),
      .data_o ({tx_stream_o.data, tx_stream_o.last_bytes, tx_stream_o.last}),
      .valid_o(tx_stream_o.valid),
      .ready_i(tx_stream_o.ready)
  );

endmodule
