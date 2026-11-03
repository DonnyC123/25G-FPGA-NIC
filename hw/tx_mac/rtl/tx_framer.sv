module tx_framer
  import pcs_pkg::*;
  import crc32_pkg::*;
#(
  parameter int MIN_FRAME_BYTES = 60
) (
  input  logic                     clk,
  input  logic                     rst,
         tx_eth_stream_if.slave    tx_stream_i,
  input  logic                     out_ready_i,
  output logic [PCS_PAYLOAD_W-1:0] out_data_o,
  output logic [PCS_SYNC_W-1:0]    out_control_o,
  output logic                     out_valid_o
);

  localparam int POS_W = LAST_BYTES_W + 1;

  if (tx_stream_i.DATA_W != PCS_PAYLOAD_W) begin : g_width_check
    $error("tx_framer expects a %0d-bit tx_stream_i, got %0d", PCS_PAYLOAD_W, tx_stream_i.DATA_W);
  end

  logic [PCS_PAYLOAD_W-1:0] stage_data;
  logic [PCS_SYNC_W-1:0]    stage_control;
  logic                     stage_valid;
  logic                     stage_end;
  logic                     stage_term;
  logic [CRC_W-1:0]         stage_fcs;
  logic [POS_W-1:0]         stage_end_pos;
  logic [LAST_BYTES_W-1:0]  stage_term_bytes;
  logic                     stage_fcs_fits;

  tx_framer_ctrl #(
      .MIN_FRAME_BYTES(MIN_FRAME_BYTES)
  ) tx_framer_ctrl_inst (
      .clk         (clk),
      .rst         (rst),
      .tx_stream_i (tx_stream_i),
      .out_ready_i (out_ready_i),
      .data_o      (stage_data),
      .control_o   (stage_control),
      .valid_o     (stage_valid),
      .end_o       (stage_end),
      .term_o      (stage_term),
      .fcs_o       (stage_fcs),
      .end_pos_o   (stage_end_pos),
      .term_bytes_o(stage_term_bytes),
      .fcs_fits_o  (stage_fcs_fits)
  );

  tx_framer_out tx_framer_out_inst (
      .clk          (clk),
      .rst          (rst),
      .out_ready_i  (out_ready_i),
      .data_i       (stage_data),
      .control_i    (stage_control),
      .valid_i      (stage_valid),
      .end_i        (stage_end),
      .term_i       (stage_term),
      .fcs_i        (stage_fcs),
      .end_pos_i    (stage_end_pos),
      .term_bytes_i (stage_term_bytes),
      .fcs_fits_i   (stage_fcs_fits),
      .out_data_o   (out_data_o),
      .out_control_o(out_control_o),
      .out_valid_o  (out_valid_o)
  );

endmodule
