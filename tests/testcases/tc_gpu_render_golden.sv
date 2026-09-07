`ifndef TC_GPU_RENDER_GOLDEN_SV
`define TC_GPU_RENDER_GOLDEN_SV

import uvm_pkg::*;
import axi4lite_pkg::*;
import clk_rst_pkg::*;
import gpu_env_pkg::*;
import gpu_seq_pkg::*;
`include "uvm_macros.svh"

// Render golden test: seeds box.memh into the DUT RAM over the host bus,
// renders one frame, reads back the ENTIRE 76800-word framebuffer over the bus,
// and hands it to the scoreboard golden sink (check_framebuffer_golden) which
// runs cmodel_run + the full C4 pixel compare. The C-model is the reference:
// any out-of-tolerance pixel is treated as a candidate DUT defect.
class tc_gpu_render_golden extends gpu_base_test;
  `uvm_component_utils(tc_gpu_render_golden)

  logic [31:0] ram_base = gpu_env_pkg::GPU_RAM_BASE;

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    // Enable the scoreboard C-model golden sink BEFORE the env (and its
    // scoreboard) is created -- UVM build is top-down, so set the config-db
    // value ahead of super.build_phase so the scb's build_phase get sees it.
    uvm_config_db#(bit)::set(this, "env.scb", "enable_cmodel_golden", 1);
    super.build_phase(phase);
  endfunction

  task run_phase(uvm_phase phase);
    int fd;
    logic [31:0] val;
    int word_count = 0;
    int unsigned st;
    string memh;
    logic [31:0] dut_fb[ROP_BUF_WORDS];
    logic [31:0] fb_base;

    phase.raise_objection(this);

    // "golden of the golden" gate. Non-zero -> UVM_WARNING and continue: the
    // self-test golden is not yet implemented, so cmodel_selftest() returns the
    // CMODEL_SELFTEST_NI sentinel (0x7001). The DUT-vs-cmodel_fb_pixel pixel
    // compare is the authoritative check. Revisit to uvm_fatal once the
    // self-test golden lands.
    st = gpu_cmodel_pkg::cmodel_selftest();
    if (st != 0)
      `uvm_warning("GOLDEN_SELFTEST", $sformatf(
        "cmodel_selftest: NOT YET IMPLEMENTED (returned %0h) -- falling back to pixel compare as the golden check", st))
    else
      `uvm_info("GOLDEN_SELFTEST", "cmodel_selftest OK (0)", UVM_LOW)

    do_reset(5);

    // Seed the input mesh into DUT RAM over the host bus. Use get_mesh_file()
    // as the path (it already resolves +MEMH_DIR/+MEMH under the xrun CWD) so
    // the C model -- which reads the mesh from DISK, not DUT RAM -- sees the
    // same file. A CMODEL_FILE_ERROR from cmodel_run later almost always is a
    // CWD path issue -- check this first before suspecting the math.
    memh = get_mesh_file();
    `uvm_info("TC_GPU", $sformatf("tc_gpu_render_golden: mesh=%s, %0d words/frame",
              memh, ROP_BUF_WORDS), UVM_LOW)
    fd = $fopen(memh, "r");
    if (fd == 0)
      `uvm_fatal("OPEN_FAIL", $sformatf("Failed to open %s", memh))
    while (!$feof(fd)) begin
      int code = $fscanf(fd, "%h\n", val);
      if (code == 1) begin
        write_reg(ram_base + (word_count * 4), val);
        word_count++;
      end
    end
    $fclose(fd);
    `uvm_info("TC_GPU", $sformatf("Seeded %0d mesh words at 0x%08h", word_count, ram_base), UVM_LOW)

    // Render one frame to the default OUT_MEM_OFF base (render_one_frame).
    fb_base = ram_base + 32'h0001_0000;
    render_one_frame(32'h0, fb_base);

    // Read the ENTIRE framebuffer back over the host bus (exact
    // tc_gpu_multi_frame.sv:61-65 pattern).
    for (int i = 0; i < ROP_BUF_WORDS; i++) begin
      read_reg(fb_base + (i * 4));
      dut_fb[i] = last_rdata;
    end

    // Hand to the scoreboard golden sink -- runs cmodel_run(memh) once and
    // the full C4 pixel compare against cmodel_fb_pixel; PASS/FAIL is reported
    // in the scoreboard report_phase.
    env.scb.check_framebuffer_golden(memh, dut_fb);

    gpu_cmodel_pkg::cmodel_save_image("model_box.png");

    phase.drop_objection(this);
  endtask

endclass

`endif
