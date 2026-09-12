`ifndef TB_ROP_BACKEND_SV
`define TB_ROP_BACKEND_SV

module tb_rop_backend;
  import uvm_pkg::*;
  import pipe_pkg::*;
  import axi4lite_pkg::*;
  import clk_rst_pkg::*;
  import rop_backend_env_pkg::*;
  `include "uvm_macros.svh"

  // Clock & reset interface
  clk_rst_if clk_rst_i();

  wire clk   = clk_rst_i.clk;
  wire rst_n = clk_rst_i.rst_n;
  wire reset = ~rst_n;

  // DUT-boundary interfaces
  pipe_if#(.DATA_W(96)) in_if(clk, rst_n);   // (x, y, c) pixel input
  axi4lite_if           bus_if(clk, rst_n);  // DUT write-only AXI4-Lite master

  // Input-side unpacking (in_if.data layout, see rop_backend_seq_pkg.sv)
  logic [31:0]       x_i;
  logic signed [31:0] c_i;
  logic [31:0]       y_i;
  logic              valid_i;
  logic              ready_o;

  assign x_i     = in_if.data[31:0];
  assign c_i     = signed'(in_if.data[63:32]);
  assign y_i     = in_if.data[95:64];
  assign valid_i = in_if.valid;
  assign in_if.ready = ready_o;

  // Frame-buffer base offset (byte units) bound to the DUT input. Settable per
  // test via the +MEM_OFFSET=<decimal> xrun plusarg (default 0); the test-side
  // scoreboard mirror reads the same plusarg.
  logic [31:0] mem_offset = 32'h0;
  initial begin
    if ($value$plusargs("MEM_OFFSET=%d", mem_offset))
      $display("tb_rop_backend: +MEM_OFFSET= -> mem_offset=0x%0h", mem_offset);
  end

  // DUT
  axil_rop_backend dut (
    .clk                    (clk),
    .reset                  (reset),

    // to axi bus
    .rop_axi_awvalid_o      (bus_if.awvalid),
    .rop_axi_awready_i      (bus_if.awready),
    .rop_axi_awaddr_o       (bus_if.awaddr),
    .rop_axi_awprot_o       (bus_if.awprot),
    .rop_axi_wvalid_o       (bus_if.wvalid),
    .rop_axi_wready_i       (bus_if.wready),
    .rop_axi_wdata_o        (bus_if.wdata),
    .rop_axi_wstrb_o        (bus_if.wstrb),
    .rop_axi_bvalid_i       (bus_if.bvalid),
    .rop_axi_bresp_i        (bus_if.bresp),
    .rop_axi_bready_o       (bus_if.bready),
    .rop_axi_arvalid_o      (bus_if.arvalid),
    .rop_axi_arready_i      (bus_if.arready),
    .rop_axi_araddr_o       (bus_if.araddr),
    .rop_axi_arprot_o       (bus_if.arprot),
    .rop_axi_rvalid_i       (bus_if.rvalid),
    .rop_axi_rready_o       (bus_if.rready),
    .rop_axi_rdata_i        (bus_if.rdata),
    .rop_axi_rresp_i        (bus_if.rresp),

    // to/from ROP
    .x_i                    (x_i),
    .y_i                    (y_i),
    .c_i                    (c_i),
    .valid_i                (valid_i),
    .ready_o                (ready_o),

    // from front end
    .output_mem_offset_addr_i(mem_offset)
  );

  initial begin
    uvm_config_db#(virtual pipe_if #(.DATA_W(96)))::set(null, "uvm_test_top.env.in_agent*", "vif", in_if);
    uvm_config_db#(virtual axi4lite_if)::set(null, "uvm_test_top.env.out_agent*", "vif", bus_if);
    uvm_config_db#(virtual clk_rst_if)::set(null, "*", "vif", clk_rst_i);
    run_test();
  end

endmodule

`endif
