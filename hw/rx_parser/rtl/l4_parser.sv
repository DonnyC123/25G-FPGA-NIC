module l4_parser
  import pcs_pkg::*;
  import parser_pkg::*;
(
  input  logic                                    clk,
  input  logic                                    rst,
  input  rx_eth_stream_t                          eth_stream_i,
  input  logic           [OFF_W-LAST_BYTES_W-1:0] word_idx_i,
  input  logic                                    hdr_done_i,
  input  logic           [IP_PROTO_W-1:0]         proto_i,
  input  logic                                    frag_i,
  input  logic           [OFF_W-1:0]              l4_pos_i,
  output rx_eth_stream_t                          eth_stream_o,
  output logic           [OFF_W-LAST_BYTES_W-1:0] word_idx_o,
  output logic                                    hdr_done_o,
  output logic           [PORT_W-1:0]             src_port_o,
  output logic           [PORT_W-1:0]             dst_port_o,
  output logic           [IP_PROTO_W-1:0]         proto_o
);

  localparam int WORD_IDX_W = OFF_W - LAST_BYTES_W;

  localparam logic [OFF_W-1:0] SRC_REL = OFF_W'(L4_SRC_PORT_OFF);
  localparam logic [OFF_W-1:0] DST_REL = OFF_W'(L4_DST_PORT_OFF);

  logic [OFF_W-1:0]      pos;
  logic                  lane_valid;
  logic [BYTE_W-1:0]     lane_data;
  logic                  has_ports;

  logic [PORT_W-1:0]     src_port_d;
  logic [PORT_W-1:0]     src_port_q;
  logic [PORT_W-1:0]     dst_port_d;
  logic [PORT_W-1:0]     dst_port_q;
  logic                  seen_d;
  logic                  seen_q;
  logic [IP_PROTO_W-1:0] proto_q;

  rx_eth_stream_t        stream_q;
  logic                  stream_valid_q;
  logic [WORD_IDX_W-1:0] stream_idx_q;

  always_comb begin
    has_ports = hdr_done_i && !frag_i && (proto_i == IP_PROTO_TCP || proto_i == IP_PROTO_UDP);
  end

  always_comb begin
    src_port_d = src_port_q;
    dst_port_d = dst_port_q;
    seen_d     = seen_q;
    pos        = '0;
    lane_valid = 1'b0;
    lane_data  = '0;

    if (eth_stream_i.valid && word_idx_i == '0) begin
      seen_d = 1'b0;
    end

    for (int i = 0; i < ETH_DATA_BYTES; i++) begin
      pos        = {word_idx_i, LAST_BYTES_W'(i)};
      lane_valid = eth_stream_i.valid && (!eth_stream_i.last || i < int'(eth_stream_i.last_bytes));
      lane_data  = eth_stream_i.data[i*BYTE_W+:BYTE_W];

      if (lane_valid && has_ports) begin
        if (pos == l4_pos_i + SRC_REL) begin
          src_port_d[PORT_W-1-:BYTE_W] = lane_data;
        end
        if (pos == l4_pos_i + SRC_REL + 1'b1) begin
          src_port_d[BYTE_W-1:0] = lane_data;
        end
        if (pos == l4_pos_i + DST_REL) begin
          dst_port_d[PORT_W-1-:BYTE_W] = lane_data;
        end
        if (pos == l4_pos_i + DST_REL + 1'b1) begin
          dst_port_d[BYTE_W-1:0] = lane_data;
          seen_d                 = 1'b1;
        end
      end
    end
  end

  always_ff @(posedge clk) begin
    if (rst) begin
      seen_q         <= 1'b0;
      stream_valid_q <= 1'b0;
    end else begin
      seen_q         <= seen_d;
      stream_valid_q <= eth_stream_i.valid;
    end
  end

  always_ff @(posedge clk) begin
    src_port_q   <= src_port_d;
    dst_port_q   <= dst_port_d;
    proto_q      <= proto_i;
    stream_q     <= eth_stream_i;
    stream_idx_q <= word_idx_i;
  end

  always_comb begin
    eth_stream_o       = stream_q;
    eth_stream_o.valid = stream_valid_q;
  end

  assign word_idx_o = stream_idx_q;
  assign hdr_done_o = seen_q;
  assign src_port_o = src_port_q;
  assign dst_port_o = dst_port_q;
  assign proto_o    = proto_q;

endmodule
