interface tx_eth_stream_if #(
  parameter int DATA_W = 64
);

  localparam int DATA_BYTES   = DATA_W / 8;
  localparam int LAST_BYTES_W = $clog2(DATA_BYTES);

  logic [DATA_W-1:0]       data;
  logic [LAST_BYTES_W-1:0] last_bytes;
  logic                    valid;
  logic                    last;
  logic                    ready;

  modport master(
    output data,
    output last_bytes,
    output valid,
    output last,
    input  ready
  );

  modport slave(
    input  data,
    input  last_bytes,
    input  valid,
    input  last,
    output ready
  );

endinterface
