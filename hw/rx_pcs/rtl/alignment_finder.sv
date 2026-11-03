module alignment_finder
  import pcs_pkg::PCS_SYNC_W;
#(
  parameter int GOOD_COUNT   = 64,
  parameter int BAD_COUNT    = 16,
  parameter int BAD_WINDOW   = 64,
  parameter int BITSLIP_WAIT = 40
) (
  input  logic                  clk,
  input  logic                  rst,
  input  logic [PCS_SYNC_W-1:0] sync_i,
  input  logic                  sync_valid_i,

  output logic                  aligned_o,
  output logic                  bitslip_o
);

  function automatic int max(int a, int b);
    return (a > b) ? a : b;
  endfunction

  localparam int CNT_MAX = max(max(GOOD_COUNT, BAD_WINDOW), BITSLIP_WAIT);
  localparam int CNT_W   = (CNT_MAX <= 1) ? 1 : $clog2(CNT_MAX);
  localparam int BAD_W   = (BAD_COUNT <= 1) ? 1 : $clog2(BAD_COUNT + 1);

  typedef enum logic [1:0] {
    SEARCH,
    BITSLIP_HOLD,
    ALIGNED
  } state_t;

  state_t             state_d;
  state_t             state_q;

  logic   [CNT_W-1:0] sync_count_d;
  logic   [CNT_W-1:0] sync_count_q;
  logic   [BAD_W-1:0] bad_count_d;
  logic   [BAD_W-1:0] bad_count_q;
  logic               bitslip_d;
  logic               bitslip_q;
  logic               sync_allowed;

  always_comb begin
    sync_allowed = sync_i[1] ^ sync_i[0];

    state_d      = state_q;
    sync_count_d = sync_count_q;
    bad_count_d  = bad_count_q;
    bitslip_d    = 1'b0;

    if (sync_valid_i) begin
      sync_count_d = sync_count_q + 1'b1;

      unique case (state_q)
        SEARCH: begin
          if (!sync_allowed) begin
            state_d      = BITSLIP_HOLD;
            bitslip_d    = 1'b1;
            sync_count_d = '0;
          end else if (sync_count_q == CNT_W'(GOOD_COUNT - 1)) begin
            state_d      = ALIGNED;
            sync_count_d = '0;
            bad_count_d  = '0;
          end
        end

        BITSLIP_HOLD: begin
          if (sync_count_q == CNT_W'(BITSLIP_WAIT - 1)) begin
            state_d      = SEARCH;
            sync_count_d = '0;
          end
        end

        ALIGNED: begin
          if (!sync_allowed) begin
            bad_count_d = bad_count_q + 1'b1;
          end
          if (!sync_allowed && bad_count_q == BAD_W'(BAD_COUNT - 1)) begin
            state_d      = SEARCH;
            sync_count_d = '0;
          end else if (sync_count_q == CNT_W'(BAD_WINDOW - 1)) begin
            sync_count_d = '0;
            bad_count_d  = '0;
          end
        end
      endcase
    end
  end

  always_ff @(posedge clk) begin
    if (rst) begin
      state_q      <= SEARCH;
      sync_count_q <= '0;
      bad_count_q  <= '0;
      bitslip_q    <= 1'b0;
    end else begin
      state_q      <= state_d;
      sync_count_q <= sync_count_d;
      bad_count_q  <= bad_count_d;
      bitslip_q    <= bitslip_d;
    end
  end

  assign bitslip_o = bitslip_q;
  assign aligned_o = state_q == ALIGNED;

endmodule
