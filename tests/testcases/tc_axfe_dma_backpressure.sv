`timescale 1ps/1ps
import uvm_pkg::*;
import axi4lite_pkg::*;
import pipe_pkg::*;
import gpu_hs_pkg::*;
import axfe_env_pkg::*;
import axfe_seq_pkg::*;
`include "uvm_macros.svh"

// ITEM 3A — Backpressure on the DMA response (valid/ready) path.
//
// Design intent (protocol-level, no DUT-internal assumptions):
// The DMA response to the GPU is a valid/ready data transfer. Any valid/ready
// protocol must guarantee:
//   (1) Word retention: if the source asserts valid and the destination holds
//       ready low, the source holds valid + data stable until the handshake
//       completes. No word is lost.
//   (2) Ordering: words are delivered in the order the source asserted them.
//
// Strategy: for each of 4 DMA reqs, hold the DMA-rsp ready signal low for
// increasing K cycles before releasing it. The scoreboard's per-word FIFO
// checks that all 4 responses arrive in order with correct data.
//
// Note on the pipe driver change: pipe_driver's responder branch now supports
// rdy_stall_cycles (default 0 = immediately ready, backwards compatible).
// The test sets env.dma_rsp_agent.drv.rdy_stall_cycles before each DMA req.

class tc_axfe_dma_backpressure extends axfe_base_test;
  `uvm_component_utils(tc_axfe_dma_backpressure)

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  task run_phase(uvm_phase phase);
    int stalls[4];
    int c;
    stalls[0] = 5;  stalls[1] = 20;  stalls[2] = 50;  stalls[3] = 100;

    phase.raise_objection(this);

    wait(env.ctrl_agent.vif.rst_n === 1'b1);
    repeat(5) @(posedge env.ctrl_agent.vif.clk);

    `uvm_info("3A", "DMA rsp backpressure: 4 words under increasing ready=0 hold", UVM_LOW)

    // Seed 4 words at base 0 (byte addresses 0x0, 0x4, 0x8, 0xC).
    seed_memory(4);

    // Enforce exactly 4 DMA responses in check_phase (one per req).
    env.scb.expected_dma_rsp = 4;

    for (int i = 0; i < 4; i++) begin
      // Queue one stall length for the next DMA-rsp handshake (applied in order
      // by the responder). The DUT's own ready gating serializes successive
      // req/rsp cycles, so the queue's front is always the correct stall for the
      // next response.
      env.dma_rsp_agent.drv.push_rdy_stall(stalls[i]);

      // Issue the DMA req. send_dma_req drives valid/addr and returns once the
      // DUT accepts the request (ready_o high in IDLE); the DUT's own ready
      // gating then blocks any subsequent req until this one's rsp completes.
      send_dma_req(i[31:0]);

      `uvm_info("3A", $sformatf("OK: DMA req %0d accepted (rsp ready held low for %0d cycles)",
                                i, stalls[i]), UVM_LOW)
    end

    // Drain: ensure all 4 responses are consumed before check_phase (send_dma_req
    // returns at DUT-accept, not at response-consumed; the last has a 100-cycle
    // stall). Bounded so the sim never hangs.
    c = 0;
    repeat (400) begin
      @(posedge env.ctrl_agent.vif.clk);
      if (env.scb.dma_rsp_count >= 4) begin c = 1; break; end
    end
    if (!c)
      `uvm_error("3A", $sformatf("Timed out draining DMA responses (dma_rsp_count = %0d, expected 4)", env.scb.dma_rsp_count))

    `uvm_info("3A", "OK: all 4 DMA responses completed under backpressure; ordering + data verified by scoreboard", UVM_LOW)

    #100ns;
    phase.drop_objection(this);
  endtask

endclass
