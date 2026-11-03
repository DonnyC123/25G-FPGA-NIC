module async_packet_fifo #(
  parameter  int WR_DATA_W       = 64,
  parameter  int RD_DATA_W       = 256,
  parameter  int FIFO_DEPTH      = 64,
  localparam int WR_LAST_BYTES_W = $clog2(WR_DATA_W / 8),
  localparam int RD_LAST_BYTES_W = $clog2(RD_DATA_W / 8)
) (
  input  logic                       wr_clk,
  input  logic                       wr_rst,
  input  logic                       rd_clk,
  input  logic                       rd_rst,

  input  logic [WR_DATA_W-1:0]       data_i,
  input  logic [WR_LAST_BYTES_W-1:0] last_bytes_i,
  input  logic                       valid_i,
  input  logic                       commit_i,
  input  logic                       revert_i,
  output logic                       full_o,

  output logic [RD_DATA_W-1:0]       data_o,
  output logic [RD_LAST_BYTES_W-1:0] last_bytes_o,
  output logic                       last_o,
  output logic                       valid_o,
  input  logic                       ready_i
);

  localparam int WORD_W      = WR_DATA_W < RD_DATA_W ? WR_DATA_W : RD_DATA_W;
  localparam int ROW_W       = WR_DATA_W < RD_DATA_W ? RD_DATA_W : WR_DATA_W;
  localparam int LANES       = ROW_W / WORD_W;
  localparam int LANE_W      = $clog2(LANES);
  localparam int ROW_BYTES_W = $clog2(ROW_W / 8);
  localparam int ADDR_W      = $clog2(FIFO_DEPTH);
  localparam int SYNC_DEPTH  = 2;

  typedef struct packed {
    logic                   last;
    logic [ROW_BYTES_W-1:0] last_bytes;
  } fifo_meta_t;

  typedef struct packed {
    logic              ovfl;
    logic [ADDR_W-1:0] addr;
  } addr_t;

  localparam addr_t FULL_GRAY_XOR = addr_t'(3) << (ADDR_W - 1);

  function automatic addr_t bin_to_gray(input addr_t bin);
    bin_to_gray = bin ^ (bin >> 1);
  endfunction

  if (FIFO_DEPTH < 2 || (FIFO_DEPTH & (FIFO_DEPTH - 1)) != 0) begin : g_depth_check
    $error("FIFO_DEPTH must be a power of two >= 2, got %0d", FIFO_DEPTH);
  end

  if (ROW_W % WORD_W != 0 || LANES < 2 || (LANES & (LANES - 1)) != 0) begin : g_width_check
    $error("WR_DATA_W (%0d) and RD_DATA_W (%0d) must differ by a power-of-two ratio", WR_DATA_W, RD_DATA_W);
  end

  (* ram_style = "block" *)
  logic       [WORD_W-1:0]    fifo_mem          [FIFO_DEPTH*LANES];
  fifo_meta_t                 meta_mem          [FIFO_DEPTH];

  logic                       full;
  logic                       empty;
  logic                       wr_en;
  logic                       rd_en;

  logic                       wr_row_end;
  logic                       rd_row_end;
  logic       [LANE_W-1:0]    last_lane;

  logic       [LANE_W-1:0]    wr_lane_d;
  logic       [LANE_W-1:0]    wr_lane_q;
  logic       [LANE_W-1:0]    rd_lane_d;
  logic       [LANE_W-1:0]    rd_lane_q;

  addr_t                      wr_addr_d;
  addr_t                      wr_addr_q;
  addr_t                      rd_addr_d;
  addr_t                      rd_addr_q;
  addr_t                      commit_end_addr_d;
  addr_t                      commit_end_addr_q;
  addr_t                      commit_addr_d;
  addr_t                      commit_addr_q;

  addr_t                      commit_addr_gray_q;
  addr_t                      rd_addr_gray_q;
  addr_t                      commit_addr_sync  [SYNC_DEPTH];
  addr_t                      rd_addr_sync      [SYNC_DEPTH];

  fifo_meta_t                 rd_meta_q;
  logic       [RD_DATA_W-1:0] rd_data_q;

  always_comb begin
    full       = bin_to_gray(wr_addr_q) == (rd_addr_sync[SYNC_DEPTH-1] ^ FULL_GRAY_XOR);
    empty      = rd_addr_gray_q == commit_addr_sync[SYNC_DEPTH-1];
    wr_en      = valid_i && !full && !revert_i;
    rd_en      = ready_i && !empty;

    wr_row_end = WR_DATA_W == ROW_W || commit_i || wr_lane_q == '1;
    last_lane  = rd_meta_q.last ? rd_meta_q.last_bytes[ROW_BYTES_W-1-:LANE_W] : '1;
    rd_row_end = RD_DATA_W == ROW_W || rd_lane_q == last_lane;
  end

  always_comb begin
    wr_addr_d         = wr_addr_q;
    wr_lane_d         = wr_lane_q;
    rd_addr_d         = rd_addr_q;
    rd_lane_d         = rd_lane_q;
    commit_end_addr_d = commit_end_addr_q;
    commit_addr_d     = commit_addr_q;

    if (revert_i) begin
      wr_addr_d = commit_end_addr_q;
      wr_lane_d = '0;
    end

    if (wr_en) begin
      wr_lane_d = wr_row_end ? '0 : wr_lane_q + 1;
      if (wr_row_end) begin
        wr_addr_d = wr_addr_q + 1;
      end
      if (commit_i) begin
        commit_end_addr_d = wr_addr_d;
      end
    end

    if (commit_addr_q != commit_end_addr_q) begin
      commit_addr_d = commit_addr_q + 1;
    end

    if (rd_en) begin
      rd_lane_d = rd_row_end ? '0 : rd_lane_q + 1;
      if (rd_row_end) begin
        rd_addr_d = rd_addr_q + 1;
      end
    end
  end

  always_ff @(posedge wr_clk) begin
    if (wr_rst) begin
      wr_addr_q          <= '0;
      wr_lane_q          <= '0;
      commit_end_addr_q  <= '0;
      commit_addr_q      <= '0;
      commit_addr_gray_q <= '0;
    end else begin
      wr_addr_q          <= wr_addr_d;
      wr_lane_q          <= wr_lane_d;
      commit_end_addr_q  <= commit_end_addr_d;
      commit_addr_q      <= commit_addr_d;
      commit_addr_gray_q <= bin_to_gray(commit_addr_d);
    end
  end

  always_ff @(posedge rd_clk) begin
    if (rd_rst) begin
      rd_addr_q      <= '0;
      rd_lane_q      <= '0;
      rd_addr_gray_q <= '0;
    end else begin
      rd_addr_q      <= rd_addr_d;
      rd_lane_q      <= rd_lane_d;
      rd_addr_gray_q <= bin_to_gray(rd_addr_d);
    end
  end

  shift_reg #(
      .DATA_W    ($bits(addr_t)),
      .PIPE_DEPTH(SYNC_DEPTH)
  ) commit_addr_sync_inst (
      .clk   (rd_clk),
      .rst   (rd_rst),
      .data_i(commit_addr_gray_q),
      .data_o(commit_addr_sync)
  );

  shift_reg #(
      .DATA_W    ($bits(addr_t)),
      .PIPE_DEPTH(SYNC_DEPTH)
  ) rd_addr_sync_inst (
      .clk   (wr_clk),
      .rst   (wr_rst),
      .data_i(rd_addr_gray_q),
      .data_o(rd_addr_sync)
  );

  if (WR_DATA_W == ROW_W) begin : g_wide_wr
    always_ff @(posedge wr_clk) begin
      if (wr_en) begin
        for (int i = 0; i < LANES; i++) begin
          fifo_mem[{wr_addr_q.addr, LANE_W'(i)}] <= data_i[i*WORD_W+:WORD_W];
        end
      end
    end
  end else begin : g_narrow_wr
    always_ff @(posedge wr_clk) begin
      if (wr_en) begin
        fifo_mem[{wr_addr_q.addr, wr_lane_q}] <= data_i;
      end
    end
  end

  if (RD_DATA_W == ROW_W) begin : g_wide_rd
    always_ff @(posedge rd_clk) begin
      for (int i = 0; i < LANES; i++) begin
        rd_data_q[i*WORD_W+:WORD_W] <= fifo_mem[{rd_addr_d.addr, LANE_W'(i)}];
      end
    end
  end else begin : g_narrow_rd
    always_ff @(posedge rd_clk) begin
      rd_data_q <= fifo_mem[{rd_addr_d.addr, rd_lane_d}];
    end
  end

  always_ff @(posedge wr_clk) begin
    if (wr_en) begin
      meta_mem[wr_addr_q.addr] <= '{last: commit_i, last_bytes: ROW_BYTES_W'({wr_lane_q, last_bytes_i})};
    end
  end

  always_ff @(posedge rd_clk) begin
    rd_meta_q <= meta_mem[rd_addr_d.addr];
  end

  always_comb begin
    full_o       = full;
    valid_o      = !empty;
    data_o       = rd_data_q;
    last_bytes_o = RD_LAST_BYTES_W'(rd_meta_q.last_bytes);
    last_o       = rd_meta_q.last && rd_row_end;
  end

endmodule
