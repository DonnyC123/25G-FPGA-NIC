module async_fifo #(
  parameter  int DATA_W     = 32,
  parameter  int FIFO_DEPTH = 16,
  localparam int ADDR_W     = $clog2(FIFO_DEPTH)
) (
  input  logic              wr_clk,
  input  logic              wr_rst,
  input  logic              rd_clk,
  input  logic              rd_rst,

  input  logic [DATA_W-1:0] data_i,
  input  logic              valid_i,
  output logic              ready_o,

  output logic [DATA_W-1:0] data_o,
  output logic              valid_o,
  input  logic              ready_i
);

  localparam int SYNC_DEPTH = 2;

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

  (* ram_style = "distributed" *)
  logic  [DATA_W-1:0] fifo_mem    [FIFO_DEPTH];

  logic               full;
  logic               empty;
  logic               wr_en;
  logic               rd_en;

  addr_t              wr_addr_d;
  addr_t              wr_addr_q;
  addr_t              rd_addr_d;
  addr_t              rd_addr_q;
  addr_t              wr_addr_gray_q;
  addr_t              rd_addr_gray_q;
  addr_t              wr_addr_sync[SYNC_DEPTH];
  addr_t              rd_addr_sync[SYNC_DEPTH];

  always_comb begin
    full      = wr_addr_gray_q == (rd_addr_sync[SYNC_DEPTH-1] ^ FULL_GRAY_XOR);
    empty     = rd_addr_gray_q == wr_addr_sync[SYNC_DEPTH-1];
    wr_en     = valid_i && !full;
    rd_en     = ready_i && !empty;

    wr_addr_d = wr_en ? wr_addr_q + 1'b1 : wr_addr_q;
    rd_addr_d = rd_en ? rd_addr_q + 1'b1 : rd_addr_q;
  end

  always_ff @(posedge wr_clk) begin
    if (wr_rst) begin
      wr_addr_q      <= '0;
      wr_addr_gray_q <= '0;
    end else begin
      wr_addr_q      <= wr_addr_d;
      wr_addr_gray_q <= bin_to_gray(wr_addr_d);
    end
  end

  always_ff @(posedge rd_clk) begin
    if (rd_rst) begin
      rd_addr_q      <= '0;
      rd_addr_gray_q <= '0;
    end else begin
      rd_addr_q      <= rd_addr_d;
      rd_addr_gray_q <= bin_to_gray(rd_addr_d);
    end
  end

  always_ff @(posedge wr_clk) begin
    if (wr_en) begin
      fifo_mem[wr_addr_q.addr] <= data_i;
    end
  end

  shift_reg #(
      .DATA_W    ($bits(addr_t)),
      .PIPE_DEPTH(SYNC_DEPTH)
  ) wr_addr_sync_inst (
      .clk   (rd_clk),
      .rst   (rd_rst),
      .data_i(wr_addr_gray_q),
      .data_o(wr_addr_sync)
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

  always_comb begin
    ready_o = !full;
    valid_o = !empty;
    data_o  = fifo_mem[rd_addr_q.addr];
  end

endmodule
