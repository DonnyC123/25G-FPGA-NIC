module async_packet_fifo #(
  parameter  int DATA_W       = 256,
  parameter  int FIFO_DEPTH   = 64,
  localparam int LAST_BYTES_W = $clog2(DATA_W / 8)
) (
  input  logic                    s_clk,
  input  logic                    s_rst,
  input  logic                    m_clk,
  input  logic                    m_rst,

  input  logic [DATA_W-1:0]       data_i,
  input  logic [LAST_BYTES_W-1:0] last_bytes_i,
  input  logic                    valid_i,
  input  logic                    commit_i,
  input  logic                    revert_i,
  output logic                    full_o,

  output logic [DATA_W-1:0]       data_o,
  output logic [LAST_BYTES_W-1:0] last_bytes_o,
  output logic                    last_o,
  output logic                    valid_o,
  input  logic                    ready_i
);

  localparam int ADDR_W     = $clog2(FIFO_DEPTH);
  localparam int SYNC_DEPTH = 2;

  typedef struct packed {
    logic                    last;
    logic [LAST_BYTES_W-1:0] last_bytes;
    logic [DATA_W-1:0]       data;
  } fifo_row_t;

  typedef struct packed {
    logic              ovfl;
    logic [ADDR_W-1:0] addr;
  } addr_t;

  function automatic addr_t bin_to_gray(input addr_t bin);
    bin_to_gray = bin ^ (bin >> 1);
  endfunction

  if (FIFO_DEPTH < 2 || (FIFO_DEPTH & (FIFO_DEPTH - 1)) != 0) begin : g_depth_check
    $error("FIFO_DEPTH must be a power of two >= 2, got %0d", FIFO_DEPTH);
  end

  fifo_row_t fifo_mem               [FIFO_DEPTH];

  logic      full;
  logic      empty;
  logic      rd_en;
  logic      wr_en;
  logic      commit;

  addr_t     wr_addr_d;
  addr_t     wr_addr_q;

  addr_t     rd_addr_d;
  addr_t     rd_addr_q;

  addr_t     commit_end_addr_d;
  addr_t     commit_end_addr_q;

  addr_t     commit_addr_d;
  addr_t     commit_addr_q;

  addr_t     commit_addr_gray_q;
  addr_t     rd_addr_gray_q;

  addr_t     commit_addr_sync_q     [SYNC_DEPTH];
  addr_t     rd_addr_sync_q         [SYNC_DEPTH];

  addr_t     wr_addr_gray;
  addr_t     rd_addr_sync_full_cmp;

  fifo_row_t rd_row_q;

  always_comb begin
    rd_en  = ready_i && !empty;
    wr_en  = valid_i && !full && !revert_i;
    commit = wr_en && commit_i;
  end

  always_comb begin
    wr_addr_d         = wr_addr_q;
    rd_addr_d         = rd_addr_q;
    commit_end_addr_d = commit_end_addr_q;
    commit_addr_d     = commit_addr_q;

    if (revert_i) begin
      wr_addr_d = commit_end_addr_q;
    end

    if (wr_en) begin
      wr_addr_d = wr_addr_q + 1;
    end

    if (commit) begin
      commit_end_addr_d = wr_addr_d;
    end

    if (commit_addr_q != commit_end_addr_q) begin
      commit_addr_d = commit_addr_q + 1;
    end

    if (rd_en) begin
      rd_addr_d = rd_addr_q + 1;
    end
  end

  always_ff @(posedge s_clk) begin
    if (s_rst) begin
      wr_addr_q          <= '0;
      commit_end_addr_q  <= '0;
      commit_addr_q      <= '0;
      commit_addr_gray_q <= '0;
    end else begin
      wr_addr_q          <= wr_addr_d;
      commit_end_addr_q  <= commit_end_addr_d;
      commit_addr_q      <= commit_addr_d;
      commit_addr_gray_q <= bin_to_gray(commit_addr_d);
    end
  end

  always_ff @(posedge m_clk) begin
    if (m_rst) begin
      rd_addr_q      <= '0;
      rd_addr_gray_q <= '0;
    end else begin
      rd_addr_q      <= rd_addr_d;
      rd_addr_gray_q <= bin_to_gray(rd_addr_d);
    end
  end

  always_ff @(posedge s_clk) begin
    if (wr_en) begin
      fifo_mem[wr_addr_q.addr] <= '{last: commit_i, last_bytes: last_bytes_i, data: data_i};
    end
  end

  always_ff @(posedge m_clk) begin
    rd_row_q <= fifo_mem[rd_addr_d.addr];
  end

  always_ff @(posedge m_clk) begin
    if (m_rst) begin
      commit_addr_sync_q <= '{default: '0};
    end else begin
      commit_addr_sync_q[1] <= commit_addr_sync_q[0];
      commit_addr_sync_q[0] <= commit_addr_gray_q;
    end
  end

  always_ff @(posedge s_clk) begin
    if (s_rst) begin
      rd_addr_sync_q <= '{default: '0};
    end else begin
      rd_addr_sync_q[1] <= rd_addr_sync_q[0];
      rd_addr_sync_q[0] <= rd_addr_gray_q;
    end
  end

  always_comb begin
    wr_addr_gray = bin_to_gray(wr_addr_q);

    rd_addr_sync_full_cmp = '{
        ovfl: ~rd_addr_sync_q[1].ovfl,
        addr: rd_addr_sync_q[1].addr ^ (ADDR_W'(1) << (ADDR_W - 1))
    };

    full  = (wr_addr_gray == rd_addr_sync_full_cmp);
    empty = (rd_addr_gray_q == commit_addr_sync_q[1]);
  end

  assign full_o = full;

  always_comb begin
    data_o       = rd_row_q.data;
    last_bytes_o = rd_row_q.last_bytes;
    last_o       = rd_row_q.last;
    valid_o      = !empty;
  end

endmodule
