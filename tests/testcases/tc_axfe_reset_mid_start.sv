`timescale 1ps/1ps
import uvm_pkg::*;
import axi4lite_pkg::*;
import pipe_pkg::*;
import gpu_hs_pkg::*;
import axfe_env_pkg::*;
import axfe_seq_pkg::*;
`include "uvm_macros.svh"

// Reset-mid-START test — the AXFE work-order item 2D.
//
// Goal: latch a START command in the DUT (Reg0 start bit = 1) while the GPU is
// NOT ready (gpu_hs.done = 0), so the DUT's `gpu_sm` sits in state `START`
// holding the start latch but with `gpu_start_o` still LOW (the GPU has not
// actually been launched). Then assert a DUT reset and verify:
//   (a) The DUT comes back to reset values: reading Reg0..Reg4 all reads
//       back as their reset value (per `tc_axfe_reset_behavior`, all 0) —
//       including Reg0, proving the start latch was cleared by reset.
//   (b) No `gpu_start` leak pulses across the reset boundary (a start that
//       "fires" the GPU even though the DUT was reset is a contract defect).
//
// If (a) or (b) fails (Reg0 readback non-zero, or a gpu_start pulse across the
// boundary), the test REDs (scoreboard / assert_no_start_pulse) and the run
// should be recorded in the work order's Item 2D Notes as a candidate DUT
// defect for the W6 reset-contract decision.
//
// Implementation notes:
//   - The CTRL write path is driven through the normal sequencer
//     (`write_reg`, `axfe_base_test.sv:105-113`). Unlike 2A/2B, the write
//     (and its B response) is handled by `bus_sm` independently of `gpu_sm`,
//     so the sequencer never hangs: reset cannot stall a `drive_*` thread here.
//     No vif-direct / disable_fork workaround is needed (the 2A/2B hazard does
//     not apply to this path).
//   - `gpu_sm` (axil_control.sv:151-225): `regf_start_i` (Reg0 bit0) takes
//     `IDLE->START`; `gpu_start_o` is combinational and only high in `state==
//     START && gpu_ready_i==1`. With `done` held 0 (GPU not ready) the DUT
//     parks in `START` and never launches the GPU — exactly the armed-but-not-
//     started condition 2D targets.
//   - Reset clears `state <= RESET` (axil_control.sv:171-174) and the whole
//     regfile `registers[i] <= '0` (axil_control.sv:382-383), so the start
//     latch is dropped and Reg0 reads back 0 after reset. Expected = benign
//     (dropped) case.
//   - No 2C-style scoreboard `model_reset()` change is needed: the start latch
//     is purely internal DUT state (no in-flight bus/DMA request is orphaned),
//     and `model_reset()` already zeroes the cached regfile model, so the
//     Reg0 readback expectation of 0 is correct.
//   - A `set_done(1'b0)` is issued explicitly before arming, so `gpu_ready_i`
//     is deterministically low (not X) and the DUT stays in START rather than
//     racing into an immediate launch.
//   - We do NOT sample a DUT-internal state name; the test is written in terms
//     of observable on-the-wire events (start latch write, settle, no-pulse,
//     `do_reset`, subsequent reset-value readback + no start pulse).

class tc_axfe_reset_mid_start extends axfe_base_test;
  `uvm_component_utils(tc_axfe_reset_mid_start)

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  task run_phase(uvm_phase phase);
    phase.raise_objection(this);

    // 1. Wait for reset release and let the DUT settle.
    wait(env.ctrl_agent.vif.rst_n === 1'b1);
    repeat (5) @(posedge env.ctrl_agent.vif.clk);

    `uvm_info("2D", "Reset-mid-START test: assert reset with a start latched (gpu not ready, DUT in START, gpu_start low)", UVM_LOW);

    // 2. Make "GPU not ready" explicit and deterministic: done=0 keeps the DUT
    //    in START (gpu_start_o = START && ready_i => 0) instead of racing into
    //    an immediate launch.
    set_done(1'b0);
    repeat (2) @(posedge env.ctrl_agent.vif.clk);

    // 3. Latch the start command: write Reg0 start bit. `bus_sm` commits this
    //    independently of `gpu_sm` (B response returns normally, no sequencer
    //    hang); `gpu_sm` transitions IDLE->START on the regf_start_i bit. With
    //    done=0 the DUT holds the start latch in START but never asserts
    //    gpu_start_o — the armed-but-not-started condition 2D targets.
    write_reg(32'h00, 32'h1);
    repeat (3) @(posedge env.ctrl_agent.vif.clk);
    `uvm_info("2D", "Start latched (Reg0 bit0=1, gpu not ready -> DUT in START, gpu_start low); asserting reset", UVM_LOW);

    // 4. Pre-reset sanity: no `gpu_start` may fire while the command is
    //    latched but the GPU is not ready (guards a DUT that would launch an
    //    un-ready start early).
    assert_no_start_pulse(25);
    `uvm_info("2D", "OK: no premature gpu_start while latched-but-not-ready (pre-reset sanity)", UVM_LOW);

    // 5. Assert the DUT reset while in START holding the start latch. Reset
    //    drops the latch (state<=RESET, regfile<=0) so no launch occurs;
    //    do_reset also calls reset_scb_model() (-> model_reset()) so the
    //    scoreboard's cached regfile model matches the reset state (all regs 0).
    do_reset(5);

    // 6. Let the DUT settle out of reset.
    repeat (5) @(posedge env.ctrl_agent.vif.clk);

    // 7. No `gpu_start` pulse may fire across the reset boundary (leak check).
    assert_no_start_pulse(50);
    `uvm_info("2D", "OK: no gpu_start leak across the reset boundary", UVM_LOW);

    // 8. DUT is back to reset values: read every register; the scoreboard
    //    (reset by `do_reset`) expects all 5 regs to read 0 on readback.
    //    Reading Reg0 specifically proves the start latch did not survive the
    //    reset (the "leak" case would read back 32'h1). No in-flight CTRL read
    //    is pending, so read order is irrelevant (unlike 2B).
    read_reg(32'h00);
    read_reg(32'h04);
    read_reg(32'h08);
    read_reg(32'h0C);
    read_reg(32'h10);
    `uvm_info("2D", "OK: post-reset readback complete (scoreboard-checked)", UVM_LOW);

    // 9. Leave the environment clean.
    set_done(1'b0);
    #100ns;
    phase.drop_objection(this);
  endtask

endclass
