`timescale 1ps/1ps
import uvm_pkg::*;
import axi4lite_pkg::*;
import pipe_pkg::*;
import gpu_hs_pkg::*;
import axfe_env_pkg::*;
import axfe_seq_pkg::*;
`include "uvm_macros.svh"

// ITEM 3C - DMA read timeout / error handling.
//
// Design intent (protocol-level, per the DESIGN INTENT convention in this work
// order: infer behavior from the interface protocol + standard HW practice,
// do not trust DUT internals):
//
//   Part A - slave backpressure. The DMA slave (memory model) responds 20 AXI
//     cycles late. General HW practice: a read master must wait for a slow
//     slave (not abort); data arrives once the slave responds. The scoreboard
//     checks the response data. EXPECTED GREEN.
//
//   Part B - large-latency slave (DEFECT CHECK, expected-RED). The DMA slave
//     is stalled for 10000 cycles - far beyond any bounded service window a
//     read master would reasonably wait. A read master with a sound design
//     MUST time out / abort an outstanding DMA read rather than wait
//     indefinitely (an unbounded WAIT_ACK on wb_ack_i can dead-lock the GPU
//     pipeline if the slave ever fails to respond). The current DUT
//     (axil_dma_master, WAIT_ACK in axil_dma.sv:119-128) has NO timeout
//     counter or abort path - it waits on wb_ack_i until the slave answers.
//
//     Per user decision 2026-09-02 this is a DUT DEFICIENCY, not an open
//     design question. Part B therefore ASSERTS a bounded response window:
//     it issues one DMA req against a stalled slave, waits a bounded number
//     of cycles for the response, and raises a UVM_ERROR if the DUT has not
//     completed the read (i.e. it is hung / waiting indefinitely). The test
//     is expected-RED until a timeout / abort / error mechanism is added to
//     the DUT. A GREEN Part B means the DUT gained a working timeout that
//     completes the read within the window - treat that as the deficiency
//     being resolved.
//
//   Key test-engineering constraint: `send_dma_req()` internally blocks on the
//   DUT's `dma_ready` (=ready_o) signal, which stays asserted only in
//   IDLE and de-asserts throughout READ_REQ/WAIT_ACK/DONE. If the DUT is stuck
//   in WAIT_ACK (no timeout), `send_dma_req` returns only at request-accept
//   (IDLE->READ_REQ) and never waits on the response, so the test drains on
//   `env.scb.dma_rsp_count` (bounded) to detect the hang. The bounded drain
//   is short (see B in run_phase) so a hung DUT times out the assertion
//   quickly rather than hanging the sim; a later DUT timeout mechanism that
//   completes the read within the window drains successfully and goes green.

class tc_axfe_dma_timeout extends axfe_base_test;
  `uvm_component_utils(tc_axfe_dma_timeout)
  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  task run_phase(uvm_phase phase);
    int c;
    phase.raise_objection(this);
    wait(env.ctrl_agent.vif.rst_n === 1'b1);
    repeat(5) @(posedge env.ctrl_agent.vif.clk);

    `uvm_info("3C", "DMA read timeout / error handling", UVM_LOW)

    // ----------------------------------------------------------------
    // Part A - slave responds 20 cycles late. DUT must wait, not abort.
    //
    // `send_dma_req` returns at request-accept (DUT IDLE - > READ_REQ); the
    // read round-trips to the AXI slave and back asynchronously (well over the
    // 20-cycle stall), so the test drains on dma_rsp_count (bounded). A
    // 20-cycle slave latency is well within what the DUT should absorb
    // without aborting, so this is EXPECTED GREEN.
    // ----------------------------------------------------------------
    env.mem.write(32'h0, 32'h12345678);
    env.mem.rd_stall_cycles = 20;
    send_dma_req(32'h0);

    // Drain: send_dma_req returns at request-accept, but the DUT's read response
    // round-trips asynchronously (well over the slave stall). Wait for it (bounded).
    c = 0;
    repeat (1000) begin
      @(posedge env.ctrl_agent.vif.clk);
      if (env.scb.dma_rsp_count >= 1) begin c = 1; break; end
    end
    if (!c)
      `uvm_error("3C", $sformatf("Part A - DUT did not complete the slow-slave read in 1000 cycles (dma_rsp_count = %0d)", env.scb.dma_rsp_count))
    else
      `uvm_info("3C", "OK: Part A - DUT waited for the slow slave; response consumed, data scoreboard-checked", UVM_LOW)

    // ----------------------------------------------------------------
    // Part B - DUT DEFICIENCY CHECK (expected-RED). Slave is stalled far
    // beyond any bounded service window (10000 cycles). A read master with a
    // sound design must time out / abort an outstanding DMA read rather than
    // wait indefinitely. The current DUT (axil_dma_master WAIT_ACK) has no
    // timeout / abort path and waits on wb_ack_i until the slave answers, so
    // it will NOT complete within the bounded window below -> UVM_ERROR.
    //
    // This is the expected-RED defect check: it stays RED until the DUT
    // gains a timeout / abort / error mechanism that completes the read
    // within the window (a GREEN here signals the deficiency is resolved).
    // The scoreboard's check_phase independently reports the still-pending
    // DMA req as "Unfinished DMA requests in queue" (axfe_scoreboard.sv:160).
    // ----------------------------------------------------------------
    env.mem.write(32'h4, 32'h9999AAAA);
    env.mem.rd_stall_cycles = 10000;
    send_dma_req(32'h1);

    // Bounded drain: the DUT must service the read within a bounded window
    // by either timing out / aborting or (with a future timeout mechanism)
    // completing the response. 500 cycles is comfortably above Part A's
    // 20-cycle stall and far below the 10k slave stall, so a hung DUT
    // triggers the error instead of hanging the sim.
    c = 0;
    repeat (500) begin
      @(posedge env.ctrl_agent.vif.clk);
      if (env.scb.dma_rsp_count >= 2) begin c = 1; break; end
    end
    if (!c)
      `uvm_error("3C", $sformatf("Part B - DUT deficiency: DMA read not completed within bounded window (dma_rsp_count = %0d); DUT hung in WAIT_ACK with no timeout/abort path (expected-RED until a timeout mechanism is added).", env.scb.dma_rsp_count))
    else
      `uvm_info("3C", $sformatf("OK: Part B - DUT completed DMA read within the bounded window (dma_rsp_count = %0d); timeout/abort mechanism present - deficiency resolved.", env.scb.dma_rsp_count), UVM_LOW)

    repeat (10) @(posedge env.ctrl_agent.vif.clk);
    #100ns;
    phase.drop_objection(this);
  endtask

endclass
