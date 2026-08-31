interface axi4lite_if (input logic clk, input logic rst_n);
  // AW channel
  logic [31:0] awaddr;
  logic [2:0]  awprot;
  logic        awvalid;
  logic        awready;

  // W channel
  logic [31:0] wdata;
  logic [3:0]  wstrb;
  logic        wvalid;
  logic        wready;

  // B channel
  logic [1:0]  bresp;
  logic        bvalid;
  logic        bready;

  // AR channel
  logic [31:0] araddr;
  logic [2:0]  arprot;
  logic        arvalid;
  logic        arready;

  // R channel
  logic [31:0] rdata;
  logic [1:0]  rresp;
  logic        rvalid;
  logic        rready;

  clocking mon_cb @(posedge clk);
    default input #1ns;
    input awaddr, awprot, awvalid, awready;
    input wdata, wstrb, wvalid, wready;
    input bresp, bvalid, bready;
    input araddr, arprot, arvalid, arready;
    input rdata, rresp, rvalid, rready;
  endclocking
endinterface
