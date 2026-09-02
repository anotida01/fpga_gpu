`timescale 1ps/1ps
import uvm_pkg::*;
import axi4lite_pkg::*;
import pipe_pkg::*;
import gpu_hs_pkg::*;
import axfe_env_pkg::*;
import axfe_seq_pkg::*;
`include "uvm_macros.svh"

// GPU-done INTERRUPT LIFECYCLE test (WORK_axfe_scb_refactor.md item 3B).
// This is the live-STATUS half of the reset/lifecycle split: it drives a real
// start->done so the DUT's interrupt generator (intr_gen, axil_control.sv:410-479)
// actually latches the done interrupt, then walks the full lifecycle and reads
// Reg1 (STATUS, offset 0x04) back each step:
//   1. Idle + gpu_done asserted; CPU writes Reg0 start bit -> DUT emits the
//      gpu_start pulse and completes WAIT->DONE. intr_gen captures the done
//      event (axil_control.sv:147) and LATCHES the interrupt (irq_o=1).
//      -> read Reg1, expect 1.
//      (Test signals the completion via report_gpu_done(); the scoreboard models
//      the live STATUS bit from that event, so this body carries no register-1
//      field specifics.)
//   2. CPU writes Reg2 (INT_CLR) bit0. intr_clr_gpu_done_o=registers[2][0]
//      (axil_control.sv:358) deasserts irq_o; Reg2 self-clears
//      (axil_control.sv:399). -> read Reg1, expect 0. (Read Reg2 too, expect 0.)
//   3. Assert the DUT reset. intr_gen resets (axil_control.sv:471) and the
//      regfile clears (axil_control.sv:383). -> read Reg1, expect 0.
// The scoreboard's INT_CLR write path clears the model automatically, and
// do_reset() drives model_reset(); both keep the model in lock-step with the DUT.
class tc_axfe_intr_status_lifecycle extends axfe_base_test;
  `uvm_component_utils(tc_axfe_intr_status_lifecycle)

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  task run_phase(uvm_phase phase);
    phase.raise_objection(this);

    // Wait for reset release and let the design settle.
    wait(env.ctrl_agent.vif.rst_n === 1'b1);
    repeat(5) @(posedge env.ctrl_agent.vif.clk);

    `uvm_info("3B", "Interrupt-lifecycle test: drive start->done, track live STATUS", UVM_LOW)

    // 1. Arm the FSM with gpu_done asserted (ready), then start the DUT.
    set_done(1'b1);
    repeat(2) @(posedge env.ctrl_agent.vif.clk);
    write_reg(32'h00, 32'h1);

    // 2. Observe the gpu_start pulse; the DUT then completes WAIT->DONE while
    //    gpu_done stays asserted, so intr_gen captures the done event and
    //    latches the interrupt (irq_o=1). Give the FSM + intr_gen time to settle.
    wait_start_pulse(50);
    `uvm_info("3B", "observed gpu_start pulse; DUT completed start->done", UVM_LOW)
    repeat(6) @(posedge env.ctrl_agent.vif.clk);

    // 3. Flag the latched interrupt to the scoreboard, then read Reg1 (expect 1).
    report_gpu_done();
    read_reg(32'h04);
    `uvm_info("3B", "STEP 1 OK: Reg1 = 1 after start->done (interrupt latched)", UVM_LOW)

    // 4. Clear the interrupt via INT_CLR (Reg2 bit0). The scoreboard's write
    //    path clears the model and Reg2's stored value in the same transaction.
    write_reg(32'h08, 32'h1);
    read_reg(32'h04); // expect 0
    `uvm_info("3B", "STEP 2 OK: Reg1 = 0 after INT_CLR (interrupt cleared)", UVM_LOW)
    read_reg(32'h08); // Reg2 self-cleared (W1C), expect 0
    `uvm_info("3B", "STEP 2b OK: Reg2 self-cleared after W1C write", UVM_LOW)

    // 5. Assert a hard reset: intr_gen + regfile reset. do_reset() also drives
    //    model_reset() so the scoreboard zeroes the live STATUS bit with it.
    do_reset(4);
    repeat(5) @(posedge env.ctrl_agent.vif.clk);
    read_reg(32'h04); // expect 0
    `uvm_info("3B", "STEP 3 OK: Reg1 = 0 after reset", UVM_LOW)

    set_done(1'b0);
    #100ns;
    phase.drop_objection(this);
  endtask

endclass
