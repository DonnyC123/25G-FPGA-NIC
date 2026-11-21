module tx_pack
  import pcs_pkg::BYTE_W;
(
  input  logic                clk,
  input  logic                rst,
         axi_stream_if.slave  s_axi,
         axi_stream_if.master m_axi
);

  localparam int DATA_W  = s_axi.DATA_W;
  localparam int MASK_W  = s_axi.MASK_W;
  localparam int COUNT_W = $clog2(MASK_W);
  localparam int TOTAL_W = $clog2(2 * MASK_W);

  function automatic logic [MASK_W-1:0] low_mask(input logic [TOTAL_W-1:0] bytes);
    for (int i = 0; i < MASK_W; i++) begin
      low_mask[i] = TOTAL_W'(i) < bytes;
    end
  endfunction

  logic [MASK_W-1:0][BYTE_W-1:0] in_bytes;
  logic [MASK_W-1:0][BYTE_W-1:0] carry_bytes;
  logic [2*DATA_W-1:0]           merged;
  logic [TOTAL_W-1:0]            total;
  logic                          out_ready;
  logic                          accept;

  logic [DATA_W-1:0]             carry_d;
  logic [DATA_W-1:0]             carry_q;
  logic [COUNT_W-1:0]            count_d;
  logic [COUNT_W-1:0]            count_q;
  logic                          flush_d;
  logic                          flush_q;

  logic [DATA_W-1:0]             data_d;
  logic [DATA_W-1:0]             data_q;
  logic [MASK_W-1:0]             mask_d;
  logic [MASK_W-1:0]             mask_q;
  logic                          last_d;
  logic                          last_q;
  logic                          valid_d;
  logic                          valid_q;

  always_comb begin
    for (int i = 0; i < MASK_W; i++) begin
      in_bytes[i]    = s_axi.mask[i] ? s_axi.data[i*BYTE_W+:BYTE_W] : '0;
      carry_bytes[i] = COUNT_W'(i) < count_q ? carry_q[i*BYTE_W+:BYTE_W] : '0;
    end

    total     = TOTAL_W'(count_q) + TOTAL_W'($countones(s_axi.mask));
    merged    = {DATA_W'(0), carry_bytes} | ({DATA_W'(0), in_bytes} << (count_q * BYTE_W));
    out_ready = !valid_q || m_axi.ready;
    accept    = s_axi.valid && out_ready && !flush_q;
  end

  always_comb begin
    carry_d = carry_q;
    count_d = count_q;
    flush_d = flush_q;
    data_d  = data_q;
    mask_d  = mask_q;
    last_d  = last_q;
    valid_d = valid_q && !m_axi.ready;

    if (flush_q && out_ready) begin
      data_d  = carry_q;
      mask_d  = low_mask(TOTAL_W'(count_q));
      last_d  = 1'b1;
      valid_d = 1'b1;
      count_d = '0;
      flush_d = 1'b0;
    end else if (accept) begin
      data_d  = merged[DATA_W-1:0];
      carry_d = merged[2*DATA_W-1:DATA_W];
      count_d = COUNT_W'(total - TOTAL_W'(MASK_W));
      if (s_axi.last && total <= TOTAL_W'(MASK_W)) begin
        mask_d  = low_mask(total);
        last_d  = 1'b1;
        valid_d = 1'b1;
        count_d = '0;
      end else if (total >= TOTAL_W'(MASK_W)) begin
        mask_d  = '1;
        last_d  = 1'b0;
        valid_d = 1'b1;
        flush_d = s_axi.last;
      end else begin
        carry_d = merged[DATA_W-1:0];
        count_d = COUNT_W'(total);
      end
    end
  end

  always_ff @(posedge clk) begin
    if (rst) begin
      count_q <= '0;
      flush_q <= 1'b0;
      valid_q <= 1'b0;
    end else begin
      count_q <= count_d;
      flush_q <= flush_d;
      valid_q <= valid_d;
    end
  end

  always_ff @(posedge clk) begin
    carry_q <= carry_d;
    data_q  <= data_d;
    mask_q  <= mask_d;
    last_q  <= last_d;
  end

  assign s_axi.ready = out_ready && !flush_q;
  assign m_axi.data  = data_q;
  assign m_axi.mask  = mask_q;
  assign m_axi.last  = last_q;
  assign m_axi.valid = valid_q;

endmodule
