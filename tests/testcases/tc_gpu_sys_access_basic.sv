`ifndef TC_GPU_SYS_ACCESS_BASIC_SV
`define TC_GPU_SYS_ACCESS_BASIC_SV

import uvm_pkg::*;
import axi4lite_pkg::*;
import clk_rst_pkg::*;
import gpu_env_pkg::*;
import gpu_seq_pkg::*;
`include "uvm_macros.svh"

// Port of tc_axil_sys_access to UVM env_gpu:
//  1. Seeds box.memh (input mesh) into DUT RAM over the host bus (IN region).
//  2. Configures IN_MEM_OFF and OUT_MEM_OFF (framebuffer region).
//  3. Triggers START, waits on the live GPU irq (done) line, clears INT_CLR.
//  4. Reads back the ENTIRE framebuffer (320x240 = 76800 words) over the host
//     bus and verifies it was painted by the GPU (non-zero pixels), proving the
//     full host->crossbar->GPU->RAM render + read path works end-to-end.
//
// Done detection uses the tb-level irq probe (dut.gpu0.irq_gpu), NOT a host-bus
// STATUS poll. The scoreboard mirrors that irq line for its STATUS (reg1) model,
// so no stale-status mismatch is raised.
class tc_gpu_sys_access_basic extends gpu_base_test;
  `uvm_component_utils(tc_gpu_sys_access_basic)

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  task run_phase(uvm_phase phase);
    int fd;
    logic [31:0] val;
    int word_count = 0;
    logic [31:0] ram_base = gpu_env_pkg::GPU_RAM_BASE;
    logic [31:0] fb_base  = ram_base + 32'h0001_0000;
    int non_zero = 0;

    phase.raise_objection(this);
    `uvm_info("TC_GPU", $sformatf("tc_gpu_sys_access_basic: full framebuffer = %0d words",
             ROP_BUF_WORDS), UVM_LOW)

    do_reset(5);

    // 1. Seed the input mesh over the host AXI-Lite bus
    fd = $fopen(get_mesh_file(), "r");
    if (fd == 0)
      `uvm_fatal("OPEN_FAIL", $sformatf("Failed to open %s", get_mesh_file()))
    while (!$feof(fd)) begin
      int code = $fscanf(fd, "%h\n", val);
      if (code == 1) begin
        write_reg(ram_base + (word_count * 4), val);
        word_count++;
      end
    end
    $fclose(fd);
    `uvm_info("TC_GPU", $sformatf("Seeded %0d mesh words at 0x%08h", word_count, ram_base), UVM_LOW)

    // 2, 3. Render one full frame (start -> live-irq done -> clear)
    `uvm_info("TC_GPU", "Triggering GPU render...", UVM_LOW)
    render_one_frame(32'h0, 32'h0001_0000);
    `uvm_info("TC_GPU", "Render complete (irq observed); interrupt cleared.", UVM_LOW)

    // 4. Read back the ENTIRE framebuffer and verify it was painted.
    for (int i = 0; i < ROP_BUF_WORDS; i++) begin
      read_reg(fb_base + (i * 4));
      if (last_rdata != 32'h0) non_zero++;
    end
    `uvm_info("TC_GPU", $sformatf("Full framebuffer read-back: %0d / %0d non-zero words",
             non_zero, ROP_BUF_WORDS), UVM_LOW)
    if (non_zero == 0)
      `uvm_error("EMPTY_FRAMEBUFFER", $sformatf("All %0d words are zero -- GPU did not render",
               ROP_BUF_WORDS))

    phase.drop_objection(this);
  endtask

endclass

`endif
