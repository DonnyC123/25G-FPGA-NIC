module tx_framer_out
  import pcs_pkg::*;
  import crc32_pkg::*;
#(
  localparam int POS_W = LAST_BYTES_W + 1
) (
  input  logic                     clk,
  input  logic                     rst,
  input  logic                     out_ready_i,

  input  logic [PCS_PAYLOAD_W-1:0] data_i,
  input  logic [PCS_SYNC_W-1:0]    control_i,
  input  logic                     valid_i,
  input  logic                     end_i,
  input  logic                     term_i,
  input  logic [CRC_W-1:0]         fcs_i,
  input  logic [POS_W-1:0]         end_pos_i,
  input  logic [LAST_BYTES_W-1:0]  term_bytes_i,
  input  logic                     fcs_fits_i,

  output logic [PCS_PAYLOAD_W-1:0] out_data_o,
  output logic [PCS_SYNC_W-1:0]    out_control_o,
  output logic                     out_valid_o
);

  logic [PCS_PAYLOAD_W-1:0] data_block;
  logic [PCS_PAYLOAD_W-1:0] term_block;

  logic [PCS_PAYLOAD_W-1:0] term_block_d;
  logic [PCS_PAYLOAD_W-1:0] term_block_q;

  logic [PCS_PAYLOAD_W-1:0] out_data_d;
  logic [PCS_PAYLOAD_W-1:0] out_data_q;

  logic [PCS_SYNC_W-1:0]    out_control_q;
  logic                     out_valid_q;

  logic                     take;

  tx_fcs_inserter tx_fcs_inserter_inst (
      .data_i      (data_i),
      .fcs_i       (fcs_i),
      .end_pos_i   (end_pos_i),
      .term_bytes_i(term_bytes_i),
      .fcs_fits_i  (fcs_fits_i),
      .data_block_o(data_block),
      .term_block_o(term_block)
  );

  always_comb begin
    take         = out_ready_i && valid_i;

    out_data_d   = data_i;
    term_block_d = term_block_q;

    if (end_i) begin
      out_data_d = fcs_fits_i ? term_block : data_block;
      if (take) begin
        term_block_d = term_block;
      end
    end

    if (term_i) begin
      out_data_d = term_block_q;
    end
  end

  always_ff @(posedge clk) begin
    if (rst) begin
      out_valid_q <= 1'b0;
    end else begin
      out_valid_q <= take;
    end
  end

  always_ff @(posedge clk) begin
    term_block_q  <= term_block_d;
    out_data_q    <= out_data_d;
    out_control_q <= control_i;
  end

  always_comb begin
    out_data_o    = out_data_q;
    out_control_o = out_control_q;
    out_valid_o   = out_valid_q;
  end

endmodule
