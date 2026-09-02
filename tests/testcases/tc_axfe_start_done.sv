`timescale 1ps/1ps
import uvm_pkg::*;
import axi4lite_pkg::*;
import pipe_pkg::*;
import gpu_hs_pkg::*;
import axfe_env_pkg::*;
import axfe_seq_pkg::*;
`include "uvm_macros.svh"

// Start→done control-state-machine cycle test for the front end.
// Verifies the full CONTROL register (Reg0) bit0 [start] handshake protocol:
//   1. Assert gpu_done=1 on the DUT to place the state machine in a ready
//      (IDLE) condition.
//   2. Write 1 to Reg0 bit0 (start); the DUT state machine should transition
//      IDLE→START and emit a single-cycle gpu_start pulse to the GPU core,
//      then move to WAIT. The test observes that pulse via wait_start_pulse.
//   3. With gpu_done still asserted, the DUT completes WAIT→DONE; in DONE it
//      self-clears the start bit (writes 0 back to Reg0) and returns to IDLE.
//      The done event is captured by intr_gen, so the gpu_done interrupt is
//      latched and Reg1 (STATUS) bit0 reads back as 1.
//   4. Read Reg1 (STATUS) and verify the live interrupt bit is 1. The test
//      signals the completion to the scoreboard via report_gpu_done() — the
//      scoreboard models the live STATUS bit from events, so the test body
//      carries no register-1 specifics.
//   5. Read Reg0 and verify the start bit has been auto-cleared (readback
//      value 0), confirming the self-clearing behavior required by the
//      register specification.
class tc_axfe_start_done extends axfe_base_test;
  `uvm_component_utils(tc_axfe_start_done)

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  task run_phase(uvm_phase phase);
    phase.raise_objection(this);

    // Wait for reset release
    wait(env.ctrl_agent.vif.rst_n === 1'b1);
    repeat(5) @(posedge env.ctrl_agent.vif.clk);

    `uvm_info("B6", "Start->done cycle test: verify Reg0 self-clear", UVM_LOW)

    // 1. Simulate the GPU core signaling readiness by asserting gpu_done; the
    //    state machine is now in IDLE, armed to accept a start command.
    set_done(1'b1);
    repeat(2) @(posedge env.ctrl_agent.vif.clk);

    // 2. Write 1 to the start bit (Reg0 bit[0]) via an AXI4-Lite CTRL write;
    //    this triggers the IDLE→START transition in the DUT state machine.
    write_reg(32'h00, 32'h1);

    // 3. While in START, the DUT asserts the 1-cycle gpu_start_o pulse that
    //    launches the GPU core; block until that pulse is observed (50-cycle
    //    timeout). After the pulse, the DUT is in WAIT.
    wait_start_pulse(50);
    `uvm_info("B6", "observed gpu_start pulse; DUT should be in WAIT", UVM_LOW)

    // 4. gpu_done is still asserted, so the DUT completes WAIT→DONE (simulated
    //    GPU work finishing), then DONE→IDLE, writing 0 back to Reg0 bit[0]
    //    during DONE (start-bit self-clear). Give the transitions time to settle.
    repeat(5) @(posedge env.ctrl_agent.vif.clk);

    // 5. The start->done cycle has completed: intr_gen has captured the gpu_done
    //    event and latched the interrupt, so Reg1 (STATUS) bit0 reads back as 1.
    //    Flag the completion to the scoreboard via the event hook, then read
    //    Reg1. The test body carries no register-1 specifics — the scoreboard
    //    models the live STATUS bit from the event it was told about.
    report_gpu_done();
    read_reg(32'h04);
    `uvm_info("B6", "Reg1 (STATUS) live bit verified (readback bit0 = 1)", UVM_LOW)

    // 6. Reg0 start bit was auto-cleared by the DUT (DONE state writes 0 to reg0);
    //    sync the scoreboard's stored model to match, then read Reg0 (expect 0).
    sync_reg_model(0, 32'h0);
    read_reg(32'h00);
    `uvm_info("B6", "Reg0 self-clear verified (readback = 0)", UVM_LOW)

    #50ns;
    phase.drop_objection(this);
  endtask

endclass
