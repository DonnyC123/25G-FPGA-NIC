module csum_calc
  import parser_pkg::*;
  import pcs_pkg::BYTE_W;
#(
  parameter  int DATA_W = 256,
  localparam int MASK_W = DATA_W / BYTE_W
) (
  input  logic                clk,
  input  logic                rst,
  input  logic [DATA_W-1:0]   data_i,
  input  logic [MASK_W-1:0]   mask_i,
  input  logic                last_i,
  input  logic                accept_i,
  input  parse_meta_t         meta_i,

  output csum_result_t        result_o,
  output logic                result_valid_o
);

  localparam int LANE_W     = $clog2(MASK_W + 1);
  localparam int HALF_WORDS = MASK_W / CSUM_BYTES;
  localparam int WORD_SUM_W = CSUM_W + $clog2(HALF_WORDS);
  localparam int ACC_W      = 32;
  localparam int FOLDS      = 3;

  function automatic logic [MASK_W-1:0] range_mask(input logic [OFF_W-1:0] pos, input logic [OFF_W-1:0] start,
                                                   input logic [OFF_W-1:0] stop);
    logic [OFF_W-1:0]  word_end;
    logic [LANE_W-1:0] lo;
    logic [LANE_W-1:0] hi;
    word_end = pos + OFF_W'(MASK_W);
    lo       = start <= pos ? '0 : start >= word_end ? LANE_W'(MASK_W) : LANE_W'(start - pos);
    hi       = stop <= pos ? '0 : stop >= word_end ? LANE_W'(MASK_W) : LANE_W'(stop - pos);
    for (int b = 0; b < MASK_W; b++) begin
      range_mask[b] = LANE_W'(b) >= lo && LANE_W'(b) < hi;
    end
  endfunction

  function automatic logic [WORD_SUM_W-1:0] sum_words(input logic [MASK_W-1:0][BYTE_W-1:0] data,
                                                      input logic [MASK_W-1:0] mask);
    sum_words = '0;
    for (int i = 0; i < HALF_WORDS; i++) begin
      sum_words += WORD_SUM_W'({mask[2*i] ? data[2*i] : BYTE_W'(0), mask[2*i+1] ? data[2*i+1] : BYTE_W'(0)});
    end
  endfunction

  function automatic logic [CSUM_W-1:0] fold(input logic [ACC_W-1:0] value);
    logic [ACC_W-1:0] folded;
    folded = value;
    for (int i = 0; i < FOLDS; i++) begin
      folded = ACC_W'(folded[CSUM_W-1:0]) + ACC_W'(folded[ACC_W-1:CSUM_W]);
    end
    return folded[CSUM_W-1:0];
  endfunction

  logic                  is_ipv4;
  logic                  is_ip;
  logic [OFF_W-1:0]      ip_csum_pos;
  logic [OFF_W-1:0]      addr_bytes;
  logic [MASK_W-1:0]     ip_mask;
  logic [MASK_W-1:0]     l4_mask;
  logic [OFF_W-1:0]      frame_len;

  logic [WORD_SUM_W-1:0] ip_word_d;
  logic [WORD_SUM_W-1:0] ip_word_q;
  logic [WORD_SUM_W-1:0] l4_word_d;
  logic [WORD_SUM_W-1:0] l4_word_q;
  logic                  word_valid_q;
  logic                  word_last_q;
  parse_meta_t           word_meta_q;
  logic [OFF_W-1:0]      word_len_q;

  logic [ACC_W-1:0]      ip_acc_d;
  logic [ACC_W-1:0]      ip_acc_q;
  logic [ACC_W-1:0]      l4_acc_d;
  logic [ACC_W-1:0]      l4_acc_q;
  logic                  done_d;
  logic                  done_q;
  logic [ACC_W-1:0]      ip_total_d;
  logic [ACC_W-1:0]      ip_total_q;
  logic [ACC_W-1:0]      l4_total_d;
  logic [ACC_W-1:0]      l4_total_q;
  parse_meta_t           done_meta_q;
  logic [OFF_W-1:0]      done_len_q;

  logic [OFF_W-1:0]      l4_len;
  logic [CSUM_W-1:0]     l4_csum;
  csum_result_t          result_d;
  csum_result_t          result_q;
  logic                  result_valid_q;

  always_comb begin
    is_ipv4     = meta_i.eth_ok && meta_i.ethertype == ETHERTYPE_IPV4;
    is_ip       = is_ipv4 || (meta_i.eth_ok && meta_i.ethertype == ETHERTYPE_IPV6);
    ip_csum_pos = meta_i.payload_off + OFF_W'(IPV4_CSUM_OFF);
    addr_bytes  = meta_i.ip_v6 ? OFF_W'(IPV6_ADDR_BYTES) : OFF_W'(IPV4_ADDR_BYTES);

    ip_mask     = '0;
    if (is_ipv4) begin
      ip_mask = range_mask(meta_i.pos, meta_i.payload_off, meta_i.l4_off) &
                ~range_mask(meta_i.pos, ip_csum_pos, ip_csum_pos + OFF_W'(CSUM_BYTES));
    end

    l4_mask = '0;
    if (is_ip) begin
      l4_mask = range_mask(meta_i.pos, meta_i.addr_off, meta_i.addr_off + addr_bytes);
    end
    if (meta_i.ip_ok && meta_i.l4_known) begin
      l4_mask |= range_mask(meta_i.pos, meta_i.l4_off, meta_i.l4_end) &
                 ~range_mask(meta_i.pos, meta_i.csum_pos, meta_i.csum_pos + OFF_W'(CSUM_BYTES));
    end

    ip_word_d = sum_words(data_i, ip_mask & mask_i);
    l4_word_d = sum_words(data_i, l4_mask & mask_i);
    frame_len = meta_i.pos + OFF_W'($countones(mask_i));
  end

  always_ff @(posedge clk) begin
    if (rst) begin
      word_valid_q <= 1'b0;
    end else begin
      word_valid_q <= accept_i;
    end
  end

  always_ff @(posedge clk) begin
    if (accept_i) begin
      ip_word_q   <= ip_word_d;
      l4_word_q   <= l4_word_d;
      word_last_q <= last_i;
      word_meta_q <= meta_i;
      word_len_q  <= frame_len;
    end
  end

  always_comb begin
    ip_acc_d   = ip_acc_q;
    l4_acc_d   = l4_acc_q;
    done_d     = 1'b0;
    ip_total_d = ip_total_q;
    l4_total_d = l4_total_q;

    if (word_valid_q) begin
      ip_acc_d = ip_acc_q + ACC_W'(ip_word_q);
      l4_acc_d = l4_acc_q + ACC_W'(l4_word_q);
      if (word_last_q) begin
        done_d     = 1'b1;
        ip_total_d = ip_acc_d;
        l4_total_d = l4_acc_d;
        ip_acc_d   = '0;
        l4_acc_d   = '0;
      end
    end
  end

  always_ff @(posedge clk) begin
    if (rst) begin
      ip_acc_q <= '0;
      l4_acc_q <= '0;
      done_q   <= 1'b0;
    end else begin
      ip_acc_q <= ip_acc_d;
      l4_acc_q <= l4_acc_d;
      done_q   <= done_d;
    end
  end

  always_ff @(posedge clk) begin
    ip_total_q <= ip_total_d;
    l4_total_q <= l4_total_d;
    if (done_d) begin
      done_meta_q <= word_meta_q;
      done_len_q  <= word_len_q;
    end
  end

  always_comb begin
    l4_len           = done_meta_q.l4_end - done_meta_q.l4_off;
    l4_csum          = ~fold(l4_total_q + ACC_W'(done_meta_q.l4_proto) + ACC_W'(l4_len));

    result_d         = result_q;
    result_d.ip_en   = done_meta_q.eth_ok && done_meta_q.ethertype == ETHERTYPE_IPV4 && done_meta_q.ip_ok &&
                       !done_meta_q.ip_v6 && done_len_q >= done_meta_q.l4_off;
    result_d.ip_pos  = done_meta_q.payload_off + OFF_W'(IPV4_CSUM_OFF);
    result_d.ip_csum = ~fold(ip_total_q);
    result_d.l4_en   = (done_meta_q.tcp_ok || done_meta_q.udp_ok) && !done_meta_q.csum_skip &&
                       done_len_q >= done_meta_q.l4_end;
    result_d.l4_pos  = done_meta_q.csum_pos;
    result_d.l4_csum = done_meta_q.udp_ok && l4_csum == '0 ? '1 : l4_csum;
  end

  always_ff @(posedge clk) begin
    if (rst) begin
      result_valid_q <= 1'b0;
    end else begin
      result_valid_q <= done_q;
    end
  end

  always_ff @(posedge clk) begin
    if (done_q) begin
      result_q <= result_d;
    end
  end

  always_comb begin
    result_o       = result_q;
    result_valid_o = result_valid_q;
  end

endmodule
