`ifndef TC_GPU_MULTI_FRAME_SV
`define TC_GPU_MULTI_FRAME_SV

import uvm_pkg::*;
import axi4lite_pkg::*;
import clk_rst_pkg::*;
import gpu_env_pkg::*;
import gpu_seq_pkg::*;
`include "uvm_macros.svh"

// Port of tc_multiple_frames intent to UVM env_gpu:
//  1. Seeds box.memh (input mesh) over the host bus (once).
//  2. Renders N frames, each to a DISTINCT output base.
//  3. Reads back the ENTIRE framebuffer (76800 words) after each frame and
//     asserts every frame is identical word-for-word ("same frame each time")
//     and non-empty -- stable repeated execution.
class tc_gpu_multi_frame extends gpu_base_test;
  `uvm_component_utils(tc_gpu_multi_frame)

  localparam int NUM_FRAMES = 5;
  localparam logic [31:0] FB_STRIDE = 32'h000F_0000; // one full frame apart

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  task run_phase(uvm_phase phase);
    int fd;
    logic [31:0] val;
    int word_count = 0;
    logic [31:0] ram_base = gpu_env_pkg::GPU_RAM_BASE;
    logic [31:0] fb_base[NUM_FRAMES];
    logic [31:0] frame[NUM_FRAMES][ROP_BUF_WORDS];

    phase.raise_objection(this);
    `uvm_info("TC_GPU", $sformatf("tc_gpu_multi_frame: N=%0d, %0d words/frame",
             NUM_FRAMES, ROP_BUF_WORDS), UVM_LOW)

    do_reset(5);

    // 1. Seed the input mesh (once)
    fd = $fopen("./memh/box.memh", "r");
    if (fd == 0) begin
      `uvm_fatal("OPEN_FAIL", "Failed to open ./memh/box.memh")
    end
    while (!$feof(fd)) begin
      int code = $fscanf(fd, "%h\n", val);
      if (code == 1) begin
        write_reg(ram_base + (word_count * 4), val);
        word_count++;
      end
    end
    $fclose(fd);
    `uvm_info("TC_GPU", $sformatf("Seeded %0d mesh words at 0x%08h", word_count, ram_base), UVM_LOW)

    // 2. Render N frames to distinct bases; capture the ENTIRE framebuffer each time
    for (int f = 0; f < NUM_FRAMES; f++) begin
      fb_base[f] = ram_base + 32'h0001_0000 + (f * FB_STRIDE);
      `uvm_info("TC_GPU", $sformatf("Frame %0d/%0d  fb_base=0x%08h  rendering...",
               f + 1, NUM_FRAMES, fb_base[f]), UVM_LOW)
      render_one_frame(32'h0, fb_base[f]);
      for (int i = 0; i < ROP_BUF_WORDS; i++) begin
        read_reg(fb_base[f] + (i * 4));
        frame[f][i] = last_rdata;
      end
    end

    // 3. Determinism: frame 0 must equal every other frame (whole buffer).
    `uvm_info("TC_GPU", "Checking multi-frame determinism (entire buffer)...", UVM_LOW)
    for (int f = 1; f < NUM_FRAMES; f++) begin
      int mismatches = 0, nz = 0;
      for (int i = 0; i < ROP_BUF_WORDS; i++) begin
        if (frame[f][i] != 32'h0) nz++;
        if (frame[0][i] !== frame[f][i]) begin
          mismatches++;
          if (mismatches <= 5)
            `uvm_error("FRAME_MISMATCH", $sformatf("f0 vs f%d word %0d: 0x%08h vs 0x%08h",
                       f, i, frame[0][i], frame[f][i]))
        end
      end
      if (nz == 0)
        `uvm_error("EMPTY_FRAMEBUFFER", $sformatf("Frame %0d entirely zero -- GPU did not render", f))
      if (mismatches == 0)
        `uvm_info("TC_GPU", $sformatf("Frame 0 == Frame %0d (%0d words, %0d non-zero)",
                 f, ROP_BUF_WORDS, nz), UVM_LOW)
      else
        `uvm_error("FRAME_MISMATCH", $sformatf("%0d word(s) differ between frame 0 and frame %0d",
                 mismatches, f))
    end

    `uvm_info("TC_GPU", "Multi-frame determinism test complete.", UVM_LOW)
    phase.drop_objection(this);
  endtask

endclass

`endif
