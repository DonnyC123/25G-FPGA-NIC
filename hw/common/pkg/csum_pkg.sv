package csum_pkg;
  localparam int CSUM_W          = 16;
  localparam int CSUM_BYTES      = CSUM_W / 8;
  localparam int CSUM_ACCUM_W    = 32;
  localparam int CSUM_FOLD_COUNT = 2;

  function automatic logic [CSUM_W-1:0] ones_sum_fold(input logic [CSUM_ACCUM_W-1:0] value);
    logic [CSUM_ACCUM_W-1:0] folded;
    folded = value;
    for (int i = 0; i < CSUM_FOLD_COUNT; i++) begin
      folded = CSUM_ACCUM_W'(folded[CSUM_W-1:0]) + CSUM_ACCUM_W'(folded[CSUM_ACCUM_W-1:CSUM_W]);
    end
    return folded[CSUM_W-1:0];
  endfunction

endpackage
