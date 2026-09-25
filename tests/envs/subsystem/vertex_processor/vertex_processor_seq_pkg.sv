`ifndef VERTEX_PROCESSOR_SEQ_PKG_SV
`define VERTEX_PROCESSOR_SEQ_PKG_SV

package vertex_processor_seq_pkg;
  import uvm_pkg::*;
  import pipe_pkg::*;
  import clk_rst_pkg::*;
  import vertex_processor_env_pkg::*;
  `include "uvm_macros.svh"

  // ------------------------------------------------------------------
  // Frame sequence: sends one full DMA frame (16 matrix words, 3 light
  // words, 1 count word, then N*7 vertex words) through the dma_rsp
  // sequencer. The request-driven dma_rsp driver consumes the items in
  // lockstep with the DUT's request pulses.
  // ------------------------------------------------------------------
  class vp_frame_seq extends uvm_sequence #(pipe_item);
    `uvm_object_utils(vp_frame_seq)

    int mat[16];
    int light[3];
    int vtx_words[$]; // N*7 words: groups of 4 position + 3 normal

    task body();
      if (vtx_words.size() % 7 != 0)
        `uvm_error("FRAME_SEQ", $sformatf("vtx_words size %0d is not a multiple of 7", vtx_words.size()))
      foreach (mat[i]) send_word(mat[i]);
      foreach (light[i]) send_word(light[i]);
      send_word(vtx_words.size()); // count word = number of vertex words
      foreach (vtx_words[i]) send_word(vtx_words[i]);
    endtask

    protected task send_word(input int w);
      pipe_item it;
      it = pipe_item::type_id::create("it");
      if (!it.randomize() with { delay == 0; })
        `uvm_fatal("FRAME_SEQ", "pipe_item randomize failed")
      it.addr = 0;
      it.data = 256'(w);
      start_item(it);
      finish_item(it);
    endtask

  endclass

  // ------------------------------------------------------------------
  // Base test: reset handling, the frame start/done protocol, and frame
  // send helpers shared by the concrete tests.
  // ------------------------------------------------------------------
  class vertex_processor_base_test extends uvm_test;
    `uvm_component_utils(vertex_processor_base_test)

    env_vertex_processor env;
    virtual gpu_hs_if ctrl_if;

    localparam int unsigned DONE_TIMEOUT_CYC  = 200_000;
    localparam int unsigned DRAIN_TIMEOUT_CYC = 100_000;

    function new(string name, uvm_component parent);
      super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
      super.build_phase(phase);
      env = env_vertex_processor::type_id::create("env", this);
      if (!uvm_config_db#(virtual gpu_hs_if)::get(this, "", "vif", ctrl_if))
        `uvm_fatal("TEST", "gpu_hs_if not found in config_db")
    endfunction

    // Wait for the initial reset to be released (clk_rst_ctrl drives it).
    task wait_for_reset();
      repeat (10) @(posedge ctrl_if.clk);
      wait (ctrl_if.rst_n === 1'b1);
      repeat (10) @(posedge ctrl_if.clk);
    endtask

    // Re-assert reset for a few cycles (returns the DUT to IDLE).
    task do_reset();
      env.clk.apply_reset(5);
    endtask

    // Pulse start_i and wait for the DUT to leave IDLE (done deasserts).
    task start_frame();
      if (ctrl_if.done !== 1'b1)
        `uvm_warning("TEST", "gpu_done_o not asserted at frame start (DUT not in IDLE)")
      ctrl_if.start <= 1'b1;
      repeat (2) @(posedge ctrl_if.clk);
      ctrl_if.start <= 1'b0;
      begin
        int unsigned cyc = 0;
        while (ctrl_if.done === 1'b1 && cyc < DONE_TIMEOUT_CYC) begin
          @(posedge ctrl_if.clk);
          cyc++;
        end
        if (cyc >= DONE_TIMEOUT_CYC)
          `uvm_fatal("TEST", "gpu_done_o never deasserted after start (DUT did not leave IDLE)")
      end
    endtask

    // Wait for the DUT to return to IDLE (done reasserts) and for the
    // scoreboard's expected-output queues to drain. A drain timeout is
    // reported as an error (not a fatal) so the run completes and the
    // scoreboard check_phase can report what is missing.
    task wait_frame_done();
      int unsigned cyc;
      cyc = 0;
      while (ctrl_if.done !== 1'b1 && cyc < DONE_TIMEOUT_CYC) begin
        @(posedge ctrl_if.clk);
        cyc++;
      end
      if (cyc >= DONE_TIMEOUT_CYC)
        `uvm_error("TEST", "gpu_done_o not reasserted within timeout (frame did not complete)")
      cyc = 0;
      while ((env.scb.exp_pos_x.size() != 0 || env.scb.exp_shade.size() != 0) && cyc < DRAIN_TIMEOUT_CYC) begin
        @(posedge ctrl_if.clk);
        cyc++;
      end
      if (cyc >= DRAIN_TIMEOUT_CYC)
        `uvm_error("TEST", $sformatf("scoreboard drain timeout: %0d pos and %0d shade outputs still expected", env.scb.exp_pos_x.size(), env.scb.exp_shade.size()))
      repeat (10) @(posedge ctrl_if.clk);
    endtask

    // Send one full frame over the DMA channel and wait for completion.
    // The test owns scoreboard state: call env.scb.reset_state() (and push
    // any ext goldens) before calling this.
    task send_frame(input int mat[16], input int light[3], input int vtx_words[$]);
      vp_frame_seq seq;
      env.dma_rsp_agent.drv.frame_start();
      start_frame();
      seq = vp_frame_seq::type_id::create("seq");
      seq.mat       = mat;
      seq.light     = light;
      seq.vtx_words = vtx_words;
      seq.start(env.dma_rsp_agent.sqr);
      wait_frame_done();
      env.dma_rsp_agent.drv.frame_end();
    endtask

  endclass

endpackage

`endif
