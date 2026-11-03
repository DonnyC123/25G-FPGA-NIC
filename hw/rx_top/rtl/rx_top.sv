module rx_top
  import pcs_pkg::*;
#(
  parameter int DIN_W        = 64,
  parameter int GOOD_COUNT   = 64,
  parameter int BAD_COUNT    = 8,
  parameter int BITSLIP_WAIT = 40,
  parameter int FIFO_DEPTH   = 64,
  parameter int DROP_COUNT_W = 32
) (
  input  logic                    eth_clk,
  input  logic                    eth_rst,
  input  logic                    axi_clk,
  input  logic                    axi_rst,
  input  logic [DIN_W-1:0]        raw_data_i,
  input  logic                    raw_valid_i,

  output logic                    locked_o,
  output logic                    bitslip_o,

  output logic [DROP_COUNT_W-1:0] overflow_drops_o,
  output logic [DROP_COUNT_W-1:0] crc_drops_o,
  output logic [DROP_COUNT_W-1:0] pcs_drops_o,

         axi_stream_if.master     m_axi
);

  rx_eth_stream_t          pcs_stream;
  rx_eth_stream_t          eth_stream;
  rx_eth_stream_t          fifo_stream;

  logic                    frame_end;
  logic                    crc_drop;
  logic                    crc_drop_q;
  logic                    fifo_cancel;

  logic                    discard_d;
  logic                    discard_q;

  logic                    overflow_drop;
  logic                    crc_error;
  logic                    pcs_error;

  logic [DROP_COUNT_W-1:0] overflow_drops_d;
  logic [DROP_COUNT_W-1:0] overflow_drops_q;
  logic [DROP_COUNT_W-1:0] crc_drops_d;
  logic [DROP_COUNT_W-1:0] crc_drops_q;
  logic [DROP_COUNT_W-1:0] pcs_drops_d;
  logic [DROP_COUNT_W-1:0] pcs_drops_q;

  rx_pcs #(
      .DIN_W       (DIN_W),
      .GOOD_COUNT  (GOOD_COUNT),
      .BAD_COUNT   (BAD_COUNT),
      .BITSLIP_WAIT(BITSLIP_WAIT)
  ) rx_pcs_inst (
      .clk         (eth_clk),
      .rst         (eth_rst),
      .raw_data_i  (raw_data_i),
      .raw_valid_i (raw_valid_i),
      .locked_o    (locked_o),
      .bitslip_o   (bitslip_o),
      .eth_stream_o(pcs_stream)
  );

  crc_checker crc_checker_inst (
      .clk         (eth_clk),
      .rst         (eth_rst),
      .eth_stream_i(pcs_stream),
      .drop_o      (crc_drop)
  );

  data_status_pipeline #(
      .DATA_W    ($bits(pcs_stream.data) + $bits(pcs_stream.last_bytes) + $bits(pcs_stream.last)),
      .STATUS_W  ($bits(pcs_stream.valid) + $bits(pcs_stream.drop) + $bits(crc_drop)),
      .PIPE_DEPTH(1)
  ) crc_pipeline_inst (
      .clk     (eth_clk),
      .rst     (eth_rst),
      .data_i  ({pcs_stream.data, pcs_stream.last_bytes, pcs_stream.last}),
      .status_i({pcs_stream.valid, pcs_stream.drop, crc_drop}),
      .data_o  ({eth_stream.data, eth_stream.last_bytes, eth_stream.last}),
      .status_o({eth_stream.valid, eth_stream.drop, crc_drop_q})
  );

  always_comb begin
    frame_end = (eth_stream.valid && eth_stream.last) || eth_stream.drop;
    discard_d = !frame_end && (discard_q || fifo_cancel);
  end

  always_comb begin
    fifo_stream      = eth_stream;
    fifo_stream.drop = eth_stream.drop || crc_drop_q;
    if (discard_q) begin
      fifo_stream.valid = 1'b0;
    end
  end

  always_comb begin
    overflow_drop = fifo_cancel && !fifo_stream.drop;
    pcs_error     = eth_stream.drop && !discard_q;
    crc_error     = crc_drop_q && !eth_stream.drop && !discard_q;
  end

  always_comb begin
    overflow_drops_d = overflow_drops_q;
    crc_drops_d      = crc_drops_q;
    pcs_drops_d      = pcs_drops_q;

    if (overflow_drop) begin
      overflow_drops_d = overflow_drops_q + 1'b1;
    end

    if (crc_error) begin
      crc_drops_d = crc_drops_q + 1'b1;
    end

    if (pcs_error) begin
      pcs_drops_d = pcs_drops_q + 1'b1;
    end
  end

  always_ff @(posedge eth_clk) begin
    if (eth_rst) begin
      discard_q        <= 1'b0;
      overflow_drops_q <= '0;
      crc_drops_q      <= '0;
      pcs_drops_q      <= '0;
    end else begin
      discard_q        <= discard_d;
      overflow_drops_q <= overflow_drops_d;
      crc_drops_q      <= crc_drops_d;
      pcs_drops_q      <= pcs_drops_d;
    end
  end

  rx_fifo_ctrl #(
      .FIFO_DEPTH(FIFO_DEPTH)
  ) rx_fifo_ctrl_inst (
      .s_clk       (eth_clk),
      .s_rst       (eth_rst),
      .m_clk       (axi_clk),
      .m_rst       (axi_rst),
      .eth_stream_i(fifo_stream),
      .cancel_o    (fifo_cancel),
      .m_axi       (m_axi)
  );

  assign overflow_drops_o = overflow_drops_q;
  assign crc_drops_o      = crc_drops_q;
  assign pcs_drops_o      = pcs_drops_q;

endmodule
