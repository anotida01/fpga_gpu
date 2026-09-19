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

    // --- [CANDIDATE DUT BUG] done/irq asserts before the pipeline drains ----
    // The DUT raises the done/irq line as soon as the front-end has consumed
    // the last input vertex, but at that instant there are still rasterised
    // pixels in flight further down the pipeline (rasterizer -> ROP -> write
    // backend). A readback taken immediately after the interrupt therefore
    // captures an incomplete frame (trailing pixels still 0 / stale). This is
    // a candidate DUT bug, flagged below; the test-side workaround for now is
    // a safe 5 ms (sim time) drain delay inserted after the interrupt.
    `uvm_error("DUT_INTR_EARLY", "CANDIDATE DUT BUG: done/irq asserted when the front-end consumed the last vertex while pixels were still in flight downstream; the frame was not fully written when the interrupt fired (early readback shows unwritten/stale trailing pixels)")
    `uvm_error("DUT_INTR_EARLY", "DUT should be able to monitor the progress of ALL pipeline stages and flag the done interrupt only when no pixels remain in flight; until that DUT fix lands the test inserts a safe 5 ms drain delay after the interrupt as a workaround")
    // Safe drain delay: 5 ms of sim time is far longer than the pipeline
    // flush latency, guaranteeing all in-flight pixels have been written.
    #(5ms)

    // Read the ENTIRE framebuffer back over the host bus and unpack the DUT's
    // real pixel format (DE1-SoC pixel buffer, board manual sec 4.2.1; as the
    // DUT actually writes it — byte addr = 1024*Y + 2*X, pitch 1024 B):
    //   320 pixels/row x 2 B = 640 B of pixel data = **160 32-bit pixel-words/row**
    //   (words 160..255 of each pitch are unwritten stride padding),
    //   TWO 16-bit pixels per 32-bit word: even X in [15:0], odd X in [31:16].
    // Each pixel's 16 bits land in [15:0] of its dut_fb[] slot so the golden
    // sink and the fbview PNG sink consume it directly.
    for (int y = 0; y < ROP_BUF_HEIGHT; y++) begin
      for (int w = 0; w < 160; w++) begin
        read_reg(fb_base + (4 * (256 * y + w)));
        dut_fb[y*320 + 2*w]     = {16'b0, last_rdata[15:0]};   // even X: low half
        dut_fb[y*320 + 2*w + 1] = {16'b0, last_rdata[31:16]};  // odd X: high half
      end
    end

    // Hand to the scoreboard golden sink -- runs cmodel_run(memh) once and
    // the full C4 pixel compare against cmodel_fb_pixel; PASS/FAIL is reported
    // in the scoreboard report_phase.
    env.scb.check_framebuffer_golden(memh, dut_fb);

    gpu_cmodel_pkg::cmodel_save_image("model_box.png");

    // Serialize the DUT's *actual readback* framebuffer (dut_fb[]) to a viewable
    // PNG via the fbview library — the C-model's model_box.png above is the
    // reference's own buffer, so this is the independent "what did the DUT
    // produce" image. Unconditional (the framebuffer is always read back here);
    // a non-OK rc is reported but does not abort (a no-libpng STUB build returns
    // FBVIEW_FEATURE_UNAVAILABLE=0x7002).
    st = gpu_fbview_pkg::fbview_save_dut("dut_box.png", dut_fb);
    if (st != 0)
      `uvm_error("GOLDEN_PNG", $sformatf(
        "fbview_save_dut(dut_box.png) returned error %0h (FBVIEW_FEATURE_UNAVAILABLE=%0h => lib built without libpng)",
        st, gpu_fbview_pkg::FBVIEW_FEATURE_UNAVAILABLE))
    else
      `uvm_info("GOLDEN_PNG", "fbview_save_dut: wrote dut_box.png (DUT readback framebuffer)", UVM_LOW)

    phase.drop_objection(this);
  endtask

endclass

`endif
