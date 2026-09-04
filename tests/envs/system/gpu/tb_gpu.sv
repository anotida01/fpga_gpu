module tb_gpu;
  import uvm_pkg::*;
  import axi4lite_pkg::*;
  import clk_rst_pkg::*;
  import gpu_env_pkg::*;
  `include "uvm_macros.svh"

  // Clock & Reset Interface (single source of truth)
  clk_rst_if clk_rst_i();

  wire clk   = clk_rst_i.clk;
  wire rst_n = clk_rst_i.rst_n;
  wire reset = ~rst_n; // DUT reset is active-high; the clk_rst VIP uses active-low rst_n

  // Host AXI4-Lite interface (DUT's exported s00 CPU port)
  axi4lite_if host_if(clk, rst_n);

  // DUT: the full GPU system. Its only external boundary is the s00 host bus; the
  // crossbar, axil_ram0, and gpu0 are all inside and driven purely via s00.
  axil_sys_top dut (
    .clk                   (clk),
    .reset                 (reset),

    .s00_axil_awaddr       (host_if.awaddr),
    .s00_axil_awprot       (host_if.awprot),
    .s00_axil_awvalid      (host_if.awvalid),
    .s00_axil_awready      (host_if.awready),
    .s00_axil_wdata        (host_if.wdata),
    .s00_axil_wstrb        (host_if.wstrb),
    .s00_axil_wvalid       (host_if.wvalid),
    .s00_axil_wready       (host_if.wready),
    .s00_axil_bresp        (host_if.bresp),
    .s00_axil_bvalid       (host_if.bvalid),
    .s00_axil_bready       (host_if.bready),
    .s00_axil_araddr       (host_if.araddr),
    .s00_axil_arprot       (host_if.arprot),
    .s00_axil_arvalid      (host_if.arvalid),
    .s00_axil_arready      (host_if.arready),
    .s00_axil_rdata        (host_if.rdata),
    .s00_axil_rresp        (host_if.rresp),
    .s00_axil_rvalid       (host_if.rvalid),
    .s00_axil_rready       (host_if.rready)
  );

  // UVM Config DB
  initial begin
    uvm_config_db#(virtual axi4lite_if)::set(null, "*.host_agent*", "vif", host_if);
    uvm_config_db#(virtual clk_rst_if)::set(null, "*", "vif", clk_rst_i);
    run_test();
  end

endmodule
