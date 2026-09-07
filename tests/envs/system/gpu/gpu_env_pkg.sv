package gpu_env_pkg;
  import uvm_pkg::*;
  import axi4lite_pkg::*;
  import clk_rst_pkg::*;
  import gpu_cmodel_pkg::*;  // DPI-C golden sink (cmodel_run / cmodel_fb_pixel) used by gpu_scoreboard
  `include "uvm_macros.svh"

  // --- Host-bus address map (as seen on axil_sys_top's exported s00 CPU port) --
  // The 3x2 crossbar (axil_crossbar_addr, M_ADDR_WIDTH=24 auto-computed bases)
  // stacks two 16 MiB master regions from 0:
  //   m00 = shared RAM (framebuffer + vertex storage) : 0x0000_0000 - 0x00FF_FFFF
  //   m01 = GPU control register file                : 0x0100_0000 - 0x01FF_FFFF
  // (Confirmed against the legacy system tests: 'h1000000=start, 'h1000008=INT_CLR,
  //  'h1000000+16=OUT_MEM_OFF.) The control reg file is the same axil_control block
  // used by the axfe unit env; control word N is decoded from the host address as:
  //   N = (host_addr - GPU_CTRL_BASE) >> 2
  //   0x00 CONTROL   0x04 STATUS  0x08 INT_CLR  0x0C IN_MEM_OFF  0x10 OUT_MEM_OFF
  localparam logic [31:0] GPU_RAM_BASE  = 32'h0000_0000;
  localparam logic [31:0] GPU_CTRL_BASE = 32'h0100_0000;

  `include "gpu_scoreboard.sv"
  `include "env_gpu.sv"
endpackage
