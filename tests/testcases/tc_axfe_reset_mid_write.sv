`timescale 1ps/1ps
import uvm_pkg::*;
import axi4lite_pkg::*;
import pipe_pkg::*;
import gpu_hs_pkg::*;
import axfe_env_pkg::*;
import axfe_seq_pkg::*;
`include "uvm_macros.svh"

// Reset-mid-write test — the AXFE work-order item 2A.
//
// Goal: assert a DUT reset while a CTRL write is in flight — specifically in
// the "AW accepted by the bridge, W not yet presented" window — and verify:
//   (a) The DUT comes back to reset values: reading Reg0..Reg4 all reads
//       back as their reset value (per `tc_axfe_reset_behavior`, all 0).
//   (b) No `gpu_start` leak pulses across the reset boundary.
//   (c) The in-flight write did not land (Reg3 == reset value).
//
// If (a) or (c) fails (Reg3 reads 32'h12345678 — the "leak" case), the
// test REDs via the scoreboard, and the run should be recorded in the work
// order's Item 2A Notes as a candidate DUT defect for the W6 reset-contract
// decision.
//
// Implementation notes:
//   - The in-flight write is driven DIRECTLY on the virtual interface and
//     never handed to the sequencer. This is deliberate: the sequencer lock
//     is what would hang at `item_done` when reset kills the DUT mid-flight,
//     and a plain `join` (or `join_any` + `disable fork`) would leave
//     dangling state. Driving the vif directly avoids all of that.
//   - The monitor (`axi4lite_monitor::monitor_write`) will latch AW, then
//     block on its W wait; it does NOT fire a scoreboard item for an aborted
//     handshake, so the scoreboard model stays untouched.
//   - The DUT's `axlite2wbsp` bridge latches AW on an awvalid && awready
//     cycle into `r_awvalid` and drops `o_axi_awready` (holding AW awaiting
//     W); `w_reset` clears `r_awvalid` (`axilwr2wbsp.v:174-175`), so the
//     in-flight AW cannot commit to the regfile across the reset.
//   - We do NOT sample a DUT-internal state name; the test is written in
//     terms of observable on-the-wire events (AW handshake, deassert,
//     `do_reset`, subsequent reset-value readback + no start pulse).

class tc_axfe_reset_mid_write extends axfe_base_test;
  `uvm_component_utils(tc_axfe_reset_mid_write)

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  task run_phase(uvm_phase phase);
    phase.raise_objection(this);

    // 1. Wait for reset release and let the DUT settle.
    wait(env.ctrl_agent.vif.rst_n === 1'b1);
    repeat (5) @(posedge env.ctrl_agent.vif.clk);

    `uvm_info("2A", "Reset-mid-CTRL-write test: assert reset while a write handshake is in flight", UVM_LOW);

    // 2. Drive AW on Reg3 (IN_MEM_OFF, 0x0C). The bridge latches AW into
    //    r_awvalid on the first awvalid && awready cycle, then drops awready
    //    (holding AW awaiting W) — this is the "AW accepted, W pending"
    //    in-flight condition 2A describes (axilwr2wbsp.v r_awvalid /
    //    o_axi_awready drop). We wait one settle cycle so the latch is
    //    registered before we deassert (normal master behavior).
    //
    //    We do NOT use the sequencer (write_reg_seq): the driver's
    //    drive_write_resp would block at `do @(posedge clk); while(!bvalid)`
    //    after we reset the DUT, holding the sequencer lock forever so the
    //    follow-up read_reg would hang. Driving the vif directly avoids that.
    env.ctrl_agent.vif.awaddr  <= 32'h0C;
    env.ctrl_agent.vif.awprot  <= 3'h0;
    env.ctrl_agent.vif.awvalid <= 1'b1;
    repeat (2) @(posedge env.ctrl_agent.vif.clk); // bridge latched AW, holding it
    `uvm_info("2A", "AW latched by bridge (holding, awaiting W); deasserting AW and asserting reset", UVM_LOW)

    // 3. Deassert AW (DUT now holds r_awvalid=1 internally). Presenting W is
    //    deliberately NOT done: keeping W un-presented IS the in-flight state.
    //    Deasserting before reset prevents the (clean, awready=1) bridge from
    //    re-latching the stale AW after reset release.
    env.ctrl_agent.vif.awvalid <= 1'b0;
    env.ctrl_agent.vif.awaddr  <= 32'h0;
    env.ctrl_agent.vif.awprot  <= 3'h0;

    // 4. Assert the DUT reset while the bridge holds the pending AW. Reset
    //    clears r_awvalid (axilwr2wbsp.v:174-175) and the regfile returns to
    //    its reset values; do_reset also calls reset_scb_model() so the
    //    scoreboard model matches the reset state.
    do_reset(5);

    // 5. Let the DUT settle out of reset.
    repeat (5) @(posedge env.ctrl_agent.vif.clk);

    // 6. No `gpu_start` pulse may fire across the reset boundary (leak check).
    assert_no_start_pulse(50);
    `uvm_info("2A", "OK: no gpu_start leak across the reset boundary", UVM_LOW);

    // 7. DUT is back to reset values: read every register; the scoreboard
    //    (reset by `do_reset`) expects all 5 regs to read 0 on readback.
    //    If the in-flight write landed across the reset (the "leak" case),
    //    Reg3 readback will be 32'h12345678 and the scoreboard will flag a
    //    mismatch for 0x0C — the human's log review records this for the
    //    W6 reset-contract decision.
    read_reg(32'h00);
    read_reg(32'h04);
    read_reg(32'h08);
    read_reg(32'h0C);
    read_reg(32'h10);
    `uvm_info("2A", "OK: post-reset readback complete (scoreboard-checked)", UVM_LOW);

    // 7. Leave the environment clean.
    set_done(1'b0);
    #100ns;
    phase.drop_objection(this);
  endtask

endclass
