package gpu_env_pkg;
  import uvm_pkg::*;
  import axi4lite_pkg::*;
  import clk_rst_pkg::*;
  import gpu_cmodel_pkg::*;  // DPI-C golden sink (cmodel_run / cmodel_fb_pixel) used by gpu_scoreboard
  import gpu_fbview_pkg::*;  // DPI-C framebuffer->PNG sink (fbview_save_dut) used by tc_gpu_render_golden
  `include "uvm_macros.svh"

  // --- Host-bus address map (as seen on axil_sys_top's exported s00 CPU port) --
  // The 3x2 crossbar (axil_crossbar_addr, M_BASE_ADDR=0 auto-computed bases)
  // stacks two master regions from 0:
  //   m00 = shared RAM (framebuffer + vertex storage) : 0x0000_0000 - 0x03FF_FFFF (64 MB)
  //   m01 = GPU control register file                : 0x0400_0000 - 0x04FF_FFFF (16 MiB)
  // m00 is a 26-bit window covering the board's 64 MB memory; m01 is 24-bit and
  // auto-aligns right after m00 (matches the legacy test_program.sv map: ctrl at
  // 0x0400_0000 over a 64 MiB cpu_mem). The control reg file is the same
  // axil_control block used by the axfe unit env; control word N is decoded from
  // the host address as:
  //   N = (host_addr - GPU_CTRL_BASE) >> 2
  //   0x00 CONTROL   0x04 STATUS  0x08 INT_CLR  0x0C IN_MEM_OFF  0x10 OUT_MEM_OFF
  localparam logic [31:0] GPU_RAM_BASE  = 32'h0000_0000;
  localparam logic [31:0] GPU_RAM_SIZE  = 32'h0400_0000; // 64 MB board memory
  localparam logic [31:0] GPU_CTRL_BASE = 32'h0400_0000;

  // --- Framebuffer geometry (DE1-SoC pixel buffer contract) -------------------
  // 320 x 240 pixels, 16-bit RGB565, two pixels per 32-bit word: 160 pixel-words
  // per row, stride padded to a 256-word (1024-byte) pitch. Single source of
  // truth for the readback loops and the scoreboard's golden W/H.
  localparam logic [31:0] GPU_FB_PITCH_BYTES = 32'd1024; // bytes per row (256 32-bit words, incl. stride padding)
  localparam logic [31:0] GPU_FB_PITCH_WORDS = 32'd256;  // words per row, incl. stride padding
  localparam logic [31:0] GPU_FB_PIXEL_WORDS = 32'd160;  // 320 px / 2 px per word
  localparam logic [31:0] GPU_FB_ROWS        = 32'd240;
  localparam logic [31:0] GPU_FB_SIZE        = GPU_FB_ROWS * GPU_FB_PITCH_BYTES; // 245760 = 0x0003_C000

  `include "gpu_scoreboard.sv"
  `include "env_gpu.sv"
endpackage
