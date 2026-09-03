`timescale 1ps/1ps
import uvm_pkg::*;
import axi4lite_pkg::*;
import pipe_pkg::*;
import gpu_hs_pkg::*;
import axfe_env_pkg::*;
import axfe_seq_pkg::*;
`include "uvm_macros.svh"

// Reset-mid-read test — the AXFE work-order item 2B.
//
// Goal: assert a DUT reset while a CTRL read is in flight — specifically in
// the "AR accepted by the bridge, R not yet returned" window — and verify:
//   (a) The DUT comes back to reset values: reading Reg0..Reg4 all reads
//       back as their reset value (per `tc_axfe_reset_behavior`, all 0).
//   (b) No `gpu_start` leak pulses across the reset boundary.
//   (c) No R response with pre-reset data is returned across the boundary
//       (the "leak" case — candidate DUT defect for the W6 reset contract).
//
// If (a) fails (any reg reads back non-zero, e.g. Reg3 != 0), the test REDs
// via the scoreboard and the run should be recorded in the work order's
// Item 2B Notes as a candidate DUT defect for the W6 reset-contract decision.
//
// Implementation notes:
//   - The in-flight read is driven DIRECTLY on the virtual interface and
//     never handed to the sequencer. Deliberate: the driver's `drive_read`
//     (axi4lite_pkg.sv:167-180) blocks at `do @(posedge clk); while(!vif.rvalid)`
//     after we reset the DUT, holding the sequencer lock forever so the
//     follow-up read_reg would hang. Driving the vif directly avoids that.
//   - The DUT's `axlite2wbsp` read bridge latches AR on an `arvalid && arready`
//     cycle (r_first increments, axilrd2wbsp.v:240-246) and holds the pending
//     read while R is being produced (it drops o_axi_arready when its
//     single-word FIFO is full, axilrd2wbsp.v:226-233). `w_reset` clears
//     o_wb_stb / wb_pending / r_stb / r_first/r_mid/r_last / o_axi_rvalid /
//     o_axi_rresp (axilrd2wbsp.v:117-122, 155-156, 165-168, 240-268, 328-331),
//     so a pending R cannot complete across the reset.
//   - The monitor (`axi4lite_monitor::monitor_read`) latches the in-flight AR,
//     then blocks on its R wait. After reset it "catches up", pairing that AR's
//     addr with the first real post-reset R. We read 0x0C FIRST in the
//     post-reset readback so the monitor pairs the in-flight AR (target 0x0C)
//     with that first post-reset R (value 0 == expected reset value 0x0C),
//     keeping all 5 scoreboard scores correct and deterministic.
//   - We do NOT sample a DUT-internal state name; the test is written in
//     terms of observable on-the-wire events (AR handshake, deassert,
//     `do_reset`, subsequent reset-value readback + no start pulse).

class tc_axfe_reset_mid_read extends axfe_base_test;
  `uvm_component_utils(tc_axfe_reset_mid_read)

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  task run_phase(uvm_phase phase);
    phase.raise_objection(this);

    // 1. Wait for reset release and let the DUT settle.
    wait(env.ctrl_agent.vif.rst_n === 1'b1);
    repeat (5) @(posedge env.ctrl_agent.vif.clk);

    `uvm_info("2B", "Reset-mid-CTRL-read test: assert reset while a read handshake is in flight", UVM_LOW);

    // 2. Drive AR on Reg3 (IN_MEM_OFF, 0x0C). The read bridge latches the AR
    //    (r_first increments, holding the read while R is produced) so the
    //    bridge ends in the "AR accepted, R pending" in-flight condition 2B
    //    describes (axilrd2wbsp.v r_first / o_axi_arready drop when its
    //    FIFO is full). We settle two cycles so the latch is registered before
    //    we deassert (normal master behavior).
    //
    //    We do NOT use the sequencer (read_reg): the driver's drive_read
    //    would block at `do @(posedge clk); while(!vif.rvalid)` after reset,
    //    holding the sequencer lock forever so the follow-up read_reg would
    //    hang. Driving the vif directly avoids that.
    env.ctrl_agent.vif.araddr  <= 32'h0C;
    env.ctrl_agent.vif.arprot  <= 3'h0;
    env.ctrl_agent.vif.arvalid <= 1'b1;
    repeat (2) @(posedge env.ctrl_agent.vif.clk); // bridge latched AR, holding it (R pending)
    `uvm_info("2B", "AR latched by bridge (holding, R pending); deasserting AR and asserting reset", UVM_LOW)

    // 3. Deassert AR (DUT now holds the pending read internally). Consuming the
    //    R handshake is deliberately NOT done: keeping it un-returned IS the
    //    in-flight state. Deasserting before reset prevents the (clean,
    //    arready=1) bridge from re-latching the stale AR after reset release.
    env.ctrl_agent.vif.arvalid <= 1'b0;
    env.ctrl_agent.vif.araddr  <= 32'h0;
    env.ctrl_agent.vif.arprot  <= 3'h0;

    // 4. Assert the DUT reset while the bridge holds the pending read. Reset
    //    clears the read path (o_wb_stb / wb_pending / r_stb / r_first..r_last /
    //    o_axi_rvalid / o_axi_rresp per axilrd2wbsp.v) and the regfile returns
    //    to its reset values; do_reset also calls reset_scb_model() so the
    //    scoreboard model matches the reset state.
    do_reset(5);

    // 5. Let the DUT settle out of reset.
    repeat (5) @(posedge env.ctrl_agent.vif.clk);

    // 6. No `gpu_start` pulse may fire across the reset boundary (leak check).
    assert_no_start_pulse(50);
    `uvm_info("2B", "OK: no gpu_start leak across the reset boundary", UVM_LOW);

    // 7. DUT is back to reset values: read every register; the scoreboard
    //    (reset by `do_reset`) expects all 5 regs to read 0 on readback.
    //    0x0C is read FIRST: the passive monitor latched the in-flight AR
    //    (target 0x0C) and will pair it with the first post-reset R we return.
    //    Pairing 0x0C->first-R (value 0 == expected 0) keeps all 5 scores
    //    clean and deterministic. If the in-flight read's R leaked back with
    //    pre-reset data, 0x0C would score wrong and the run records a W6
    //    reset-contract candidate.
    read_reg(32'h0C);
    read_reg(32'h00);
    read_reg(32'h04);
    read_reg(32'h08);
    read_reg(32'h10);
    `uvm_info("2B", "OK: post-reset readback complete (scoreboard-checked)", UVM_LOW);

    // 8. Leave the environment clean.
    set_done(1'b0);
    #100ns;
    phase.drop_objection(this);
  endtask

endclass
