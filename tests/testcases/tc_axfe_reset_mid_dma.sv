`timescale 1ps/1ps
import uvm_pkg::*;
import axi4lite_pkg::*;
import pipe_pkg::*;
import gpu_hs_pkg::*;
import axfe_env_pkg::*;
import axfe_seq_pkg::*;
`include "uvm_macros.svh"

// Reset-mid-DMA test — the AXFE work-order item 2C.
//
// Goal: assert a DUT reset while a DMA read is in flight — specifically with
// the DUT in `axil_dma_master` state `READ_REQ` / `WAIT_ACK` (a read accepted
// and pending on the WB bus, response not yet delivered to the GPU) — and
// verify:
//   (a) The DUT comes back to reset values: reading Reg0..Reg4 all reads
//       back as their reset value (per `tc_axfe_reset_behavior`, all 0).
//   (b) No `gpu_start` leak pulses across the reset boundary.
//   (c) No `dma_valid` (DUT->GPU read response) leaks back with pre-reset
//       data (the "leak" case — candidate DUT defect for the W6 reset
//       contract).
//
// If (a) fails (any reg reads back non-zero), the test REDs via the
// scoreboard and the run should be recorded in the work order's Item 2C
// Notes as a candidate DUT defect for the W6 reset-contract decision.
//
// Implementation notes:
//   - Unlike 2A/2B (CTRL path), the DMA req path is driven through its own
//     agent + sequencer (`send_dma_req`, `axfe_base_test.sv:151-155`). The
//     pipe driver (pipe_pkg.sv:51-60) waits only for the `valid/ready` req
//     handshake (DUT IDLE->READ_REQ) and does NOT wait on the response, so
//     resetting the DUT cannot hang a sequencer thread here — no
//     vif-direct / disable_fork workaround is needed (the 2A/2B hazard does
//     not apply to this path).
//   - A deterministic in-flight window is forced with the mem-model slave
//     stall: `env.mem.rd_stall_cycles = 20` holds the DMA read response late
//     (axi4lite_pkg.sv resp driver) so the DUT sits in WAIT_ACK when reset
//     lands, instead of racing a fast completion.
//   - Reset clears the DMA master: `state <= RESET`,
//     `address_i_reg <= '0`, `dma_out <= '0` (axil_dma.sv:43-59); and
//     `valid_o`/`ready_o` are only ever driven high in DONE/IDLE (axil_dma.sv:
//     62-138) — never in READ_REQ/WAIT_ACK — so no `dma_valid` response can
//     be emitted across the reset boundary. Expected = benign (dropped) case.
//   - The scoreboard model is reset by `do_reset` -> `reset_scb_model()` ->
//     `model_reset()`, which now also clears `exp_dma_addr_q` so the single
//     orphaned in-flight req (pushed by the monitor before reset) is not
//     flagged by check_phase as "unfinished". A genuine post-reset DMA
//     response is still caught: with the queue empty, write_dma_rsp raises
//     "Unexpected DMA response".
//   - We do NOT sample a DUT-internal state name; the test is written in
//     terms of observable on-the-wire events (DMA req accept, deassert,
//     `do_reset`, subsequent reset-value readback + no start pulse + no
//     leaked dma_valid).

class tc_axfe_reset_mid_dma extends axfe_base_test;
  `uvm_component_utils(tc_axfe_reset_mid_dma)

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  task run_phase(uvm_phase phase);
    phase.raise_objection(this);

    // 1. Wait for reset release and let the DUT settle.
    wait(env.ctrl_agent.vif.rst_n === 1'b1);
    repeat (5) @(posedge env.ctrl_agent.vif.clk);

    `uvm_info("2C", "Reset-mid-DMA test: assert reset while a DMA read is in flight (READ_REQ/WAIT_ACK)", UVM_LOW);

    // 2. Set up the DMA read context: seed a backing memory so a (non-dropped)
    //    response would be well-defined, and clear IN_MEM_OFF (Reg3, 0x0C) so
    //    the DUT's read address is the request word offset alone.
    seed_memory(16);
    write_reg(32'h0C, 32'h0);
    repeat (2) @(posedge env.ctrl_agent.vif.clk);

    // 3. Kick the DMA read against a deliberately slow slave. `rd_stall_cycles`
    //    holds the mem-model response 20 cycles late, so after `send_dma_req`
    //    returns (the DUT accepted the req at IDLE->READ_REQ) the DUT is parked
    //    in WAIT_ACK with the read response still outstanding — the in-flight
    //    condition 2C targets. The req is already pushed to the scoreboard's
    //    exp_dma_addr_q by the monitor.
    env.mem.rd_stall_cycles = 20;
    send_dma_req(32'h04);
    `uvm_info("2C", "DMA req accepted (DUT in READ_REQ/WAIT_ACK, response stalled); asserting reset", UVM_LOW);

    // 4. Assert the DUT reset while the DMA read is in flight. Reset drops the
    //    in-flight read (axil_dma.sv state<=RESET, dma_out<=0, valid_o can only
    //    be high in DONE/IDLE) and clears the regfile; do_reset also calls
    //    reset_scb_model() (-> model_reset()) so the scoreboard model and the
    //    orphaned pending-DMA-req queue match the reset state.
    do_reset(5);

    // 5. Let the DUT settle out of reset.
    repeat (5) @(posedge env.ctrl_agent.vif.clk);

    // 6. No `gpu_start` pulse may fire across the reset boundary (leak check).
    assert_no_start_pulse(50);
    `uvm_info("2C", "OK: no gpu_start leak across the reset boundary", UVM_LOW);

    // 7. No DMA read response with pre-reset data may be emitted by the DUT
    //    against the GPU after reset (leak check). Sample the DUT->GPU read
    //    response valid (dma_rsp_if.valid) rather than a DUT-internal state.
    //    (The req-side `ready` legitimately re-asserts with the DUT in IDLE
    //    after reset, so it is not a meaningful leak indicator; dma_valid is.)
    if (env.dma_rsp_agent.vif.valid === 1'b1)
      `uvm_error("2C", "dma_valid still asserted across the reset boundary (leaked DUT->GPU DMA response, pre-reset data) — candidate W6 reset-contract defect")
    else
      `uvm_info("2C", "OK: no leaked dma_valid response across the reset boundary", UVM_LOW);

    // 8. DUT is back to reset values: read every register; the scoreboard
    //    (reset by `do_reset`) expects all 5 regs to read 0 on readback.
    //    (No in-flight CTRL read is pending here, so read order is irrelevant
    //    — unlike 2B, there is no passive-monitor AR to pair with.)
    read_reg(32'h00);
    read_reg(32'h04);
    read_reg(32'h08);
    read_reg(32'h0C);
    read_reg(32'h10);
    `uvm_info("2C", "OK: post-reset readback complete (scoreboard-checked)", UVM_LOW);

    // 9. Leave the environment clean.
    set_done(1'b0);
    #100ns;
    phase.drop_objection(this);
  endtask

endclass
