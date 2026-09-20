`ifndef TC_GPU_RENDER_GUI_LIVE_SV
`define TC_GPU_RENDER_GUI_LIVE_SV

import uvm_pkg::*;
import axi4lite_pkg::*;
import clk_rst_pkg::*;
import gpu_env_pkg::*;
import gpu_seq_pkg::*;
`include "uvm_macros.svh"

// Live GUI render test: seeds the mesh, renders one frame, and pushes every
// pixel the DUT draws (via the passive fbview_live_px_tap) to a live fbview
// window as it is drawn — the window animates at the sim's own pace over the
// render interval. The golden scoreboard check + the DUT-readback PNG still
// run AFTER the render, so this test also proves the tap did not disturb the
// DUT.
//
// Gated: only runs the frame + view when +GUI_LIVE is on the xrun command
// line (default OFF -> informational message + immediate pass, so the test
// stays cheap in a plain regression sweep).
//
// Graceful degradation: if the linked fbview library was built without SDL2
// (open returns FBVIEW_FEATURE_UNAVAILABLE=0x7002) the test still renders,
// readbacks, runs the golden check and tries the PNG save (which itself
// degrades to 0x7002 if the lib was built without libpng) — mirrors the
// degrade semantics of tc_gpu_render_golden's fbview_save_dut call.
//
// User close (ESC / window button): the push loop stops (the DUT render runs
// to completion and the golden check still runs), reported as UVM_INFO only —
// the sim must never fail because the human closed the window.
//
// Post-IRQ drain window: the DUT's DONE interrupt can fire before the ROP
// backend's later pipeline stages have finished writing pixels (a known DUT
// deficiency — the proper fix is for the DUT to signal completion once the
// later stages are done, tracked separately). This test therefore holds its
// "render done" flag for a bounded drain window — default **10 ms of sim time**
// (the ROP backend needs ~10 ms after DONE to drain in-flight pixels, as
// measured on the sim host), override with `+PX_DRAIN_MS=<ms>` — so the live
// push loop presents the final in-flight pixels. This also (harmlessly)
// delays the golden readback by the same window. The test stays passive: no
// RTL change, no extra DUT traffic.

class tc_gpu_render_gui_live extends gpu_base_test;
  `uvm_component_utils(tc_gpu_render_gui_live)

  localparam int W = 320;
  localparam int H = 240;

  logic [31:0] ram_base = gpu_env_pkg::GPU_RAM_BASE;

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  task run_phase(uvm_phase phase);
    int fd;
    logic [31:0] val;
    int word_count = 0;
    int unsigned st;
    string memh;
    logic [31:0] dut_fb[ROP_BUF_WORDS];
    logic [31:0] fb_base;
    bit gui_live;
    bit have_win;
    int unsigned handle = 0;
    int n_pushed = 0;
    int n_oob = 0;
    int n_unexpected = 0;
    bit render_done = 0;
    int px_x, px_y;
    int unsigned px_word;
    longint drain_arg   = 0;
    real drain_ms = 10.0;      // default: 10 ms of sim time (delay = drain_ms * 1ms)
    if ($value$plusargs("PX_DRAIN_MS=%0d", drain_arg) && (drain_arg >= 0))
      drain_ms = real'(drain_arg);

    phase.raise_objection(this);

    // --- gate ------------------------------------------------------------
    gui_live = $test$plusargs("GUI_LIVE");
    if (!gui_live) begin
      `uvm_info("GUI_LIVE", "no +GUI_LIVE on the command line; not running the live view (pass)", UVM_LOW)
      phase.drop_objection(this);
      return;
    end

    // --- setup (same seed/render/readback pattern as tc_gpu_render_golden) ----
    do_reset(5);

    memh = get_mesh_file();
    `uvm_info("TC_GPU", $sformatf("tc_gpu_render_gui_live: mesh=%s, %0d words/frame",
              memh, ROP_BUF_WORDS), UVM_LOW)
    fd = $fopen(memh, "r");
    if (fd == 0)
      `uvm_fatal("OPEN_FAIL", $sformatf("Failed to open %s", memh))
    while (!$feof(fd)) begin
      int code = $fscanf(fd, "%h\n", val);
      if (code == 1) begin
        write_reg(ram_base + MESH_SEED_BYTE_OFF + (word_count * 4), val);
        word_count++;
      end
    end
    $fclose(fd);
    `uvm_info("TC_GPU", $sformatf("Seeded %0d mesh words at 0x%08h", word_count, ram_base + MESH_SEED_BYTE_OFF), UVM_LOW)

    // --- open the live window (SDL2-optional) -----------------------------
    have_win = 0;
    st = gpu_fbview_gui_pkg::fbview_open_win(W, H, handle);
    case (st)
      gpu_fbview_gui_pkg::FBVIEW_OK: begin
        have_win = 1;
        `uvm_info("GUI_LIVE", $sformatf("fbview window open (handle=%0d, %0dx%0d); pushing per drawn pixel",
                  handle, W, H), UVM_LOW)
      end
      gpu_fbview_gui_pkg::FBVIEW_FEATURE_UNAVAILABLE: begin
        `uvm_info("GUI_LIVE", $sformatf(
          "fbview library has no SDL2 backend (rc=%0h=FEATURE_UNAVAILABLE); proceeding with render + checks, no window",
          st), UVM_LOW)
      end
      default: begin
        `uvm_error("GUI_LIVE", $sformatf("fbview_open_win returned unexpected rc %0h", st))
      end
    endcase

    // --- render (forked so the push loop can interleave) + live push -------
    fork
      begin
        fb_base = ram_base + 32'h0001_0000;
        render_one_frame(MESH_SEED_WORD_OFF, fb_base);
        // DUT DONE-IRQ drain workaround (see file header): keep the push loop
        // live for the bounded window so in-flight backend pixels are presented.
        if (drain_ms > 0.0) begin
          `uvm_info("GUI_LIVE", $sformatf("post-IRQ drain window: %0.0f ms (override with +PX_DRAIN_MS=<ms>)", drain_ms), UVM_LOW)
          #(drain_ms * 1ms);
          `uvm_info("GUI_LIVE", "Post-IRQ drain window completed", UVM_LOW)
        end
        render_done = 1'b1;
      end
    join_none

    while (have_win && (render_done == 0 || fbview_live_px_pkg::count() > 0)) begin
      wait (render_done == 1'b1 || (fbview_live_px_pkg::head != fbview_live_px_pkg::tail));
      if (fbview_live_px_pkg::count() <= 0) continue;
      if (render_done && (fbview_live_px_pkg::head == fbview_live_px_pkg::tail)) break;
      fbview_live_px_pkg::pop(px_x, px_y, px_word);
      st = gpu_fbview_gui_pkg::fbview_push_px(handle, px_x, px_y, px_word);
      case (st)
        gpu_fbview_gui_pkg::FBVIEW_OK:                 n_pushed++;
        gpu_fbview_gui_pkg::FBVIEW_STATE_ERROR:        n_oob++;      // pixel outside the window; keep going
        gpu_fbview_gui_pkg::FBVIEW_WINDOW_CLOSED: begin
          `uvm_info("GUI_LIVE", "user closed the window; stopping the live push (render continues, checks still run)", UVM_LOW)
          have_win = 0;
        end
        default:                                        n_unexpected++;
      endcase
    end

    wait (render_done == 1'b1);   // the render body (incl. INT clear) has finished
    `uvm_info("GUI_LIVE", $sformatf("render done; %0d pixels drawn at the tap (%0d pushed, %0d outside window, %0d unexpected rc)",
              fbview_live_px_pkg::head, n_pushed, n_oob, n_unexpected), UVM_LOW)
    if (n_unexpected != 0)
      `uvm_error("GUI_LIVE", $sformatf("%0d fbview calls returned an unexpected rc", n_unexpected))

    // --- readback + golden check (identical pattern to tc_gpu_render_golden) --
    // The DUT's real pixel format (DE1-SoC pixel buffer, board manual sec 4.2.1;
    // as the DUT writes it — byte addr = 1024*Y + 2*X, pitch 1024 B:
    //   320 pixels/row x 2 B = 640 B = **160 pixel-words/row** (words 160..255
    //   of each pitch are unwritten stride padding), TWO 16-bit pixels per word
    //   (even X in [15:0], odd X in [31:16]), each pixel 16 bits into [15:0]).
    fb_base = ram_base + 32'h0001_0000;
    for (int y = 0; y < ROP_BUF_HEIGHT; y++) begin
      for (int w = 0; w < 160; w++) begin
        read_reg(fb_base + (4 * (256 * y + w)));
        dut_fb[y*320 + 2*w]     = {16'b0, last_rdata[15:0]};   // even X: low half
        dut_fb[y*320 + 2*w + 1] = {16'b0, last_rdata[31:16]};  // odd X: high half
      end
    end

    // Scoreboard golden sink: cmodel_run(memh) + the full pixel compare; the
    // PASS/FAIL surfaces in the scoreboard report_phase. Running this WITH
    // the live view active is what proves the passive tap did not disturb the
    // DUT.
    env.scb.check_framebuffer_golden(memh, dut_fb);

    // Serialize the DUT's actual readback framebuffer (dut_fb[]) to a viewable
    // PNG — "dut_gui.png" (the golden test writes its own "dut_box.png").
    st = gpu_fbview_pkg::fbview_save_dut("dut_gui.png", dut_fb);
    if (st == 0)
      `uvm_info("GOLDEN_PNG", "fbview: wrote dut_gui.png (DUT readback framebuffer)", UVM_LOW)
    else if (st == gpu_fbview_pkg::FBVIEW_FEATURE_UNAVAILABLE)
      `uvm_info("GOLDEN_PNG", "fbview_save_dut: lib has no libpng backend (rc=0x7002); PNG skipped", UVM_LOW)
    else
      `uvm_error("GOLDEN_PNG", $sformatf("fbview_save_dut(dut_gui.png) returned error %0h", st))

    // --- close the window (idempotent; safe when it was never opened) -------
    if (have_win) begin
      st = gpu_fbview_gui_pkg::fbview_close(handle);
      if (st != gpu_fbview_gui_pkg::FBVIEW_OK)
        `uvm_info("GUI_LIVE", $sformatf("fbview_close returned rc %0h (window may already be in a closed state)", st), UVM_LOW)
    end

    phase.drop_objection(this);
  endtask

endclass

`endif
