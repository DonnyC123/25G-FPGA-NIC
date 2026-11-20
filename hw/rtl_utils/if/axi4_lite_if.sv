interface axi4_lite_if #(
  parameter int DATA_W = 32,
  parameter int ADDR_W = 32
);

  localparam int STRB_W = DATA_W / 8;
  localparam int PROT_W = 3;
  localparam int RESP_W = 2;

  logic [ADDR_W-1:0] awaddr;
  logic [PROT_W-1:0] awprot;
  logic              awvalid;
  logic              awready;

  logic [DATA_W-1:0] wdata;
  logic [STRB_W-1:0] wstrb;
  logic              wvalid;
  logic              wready;

  logic [RESP_W-1:0] bresp;
  logic              bvalid;
  logic              bready;

  logic [ADDR_W-1:0] araddr;
  logic [PROT_W-1:0] arprot;
  logic              arvalid;
  logic              arready;

  logic [DATA_W-1:0] rdata;
  logic [RESP_W-1:0] rresp;
  logic              rvalid;
  logic              rready;

  modport master(
    output awaddr,
    output awprot,
    output awvalid,
    input  awready,
    output wdata,
    output wstrb,
    output wvalid,
    input  wready,
    input  bresp,
    input  bvalid,
    output bready,
    output araddr,
    output arprot,
    output arvalid,
    input  arready,
    input  rdata,
    input  rresp,
    input  rvalid,
    output rready
  );

  modport slave(
    input  awaddr,
    input  awprot,
    input  awvalid,
    output awready,
    input  wdata,
    input  wstrb,
    input  wvalid,
    output wready,
    output bresp,
    output bvalid,
    input  bready,
    input  araddr,
    input  arprot,
    input  arvalid,
    output arready,
    output rdata,
    output rresp,
    output rvalid,
    input  rready
  );

endinterface
