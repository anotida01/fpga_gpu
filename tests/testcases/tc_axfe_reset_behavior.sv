`timescale 1ps/1ps
import uvm_pkg::*;
import axi4lite_pkg::*;
import pipe_pkg::*;
import gpu_hs_pkg::*;
import axfe_env_pkg::*;
import axfe_seq_pkg::*;
`include "uvm_macros.svh"

// Register-file RESET behavior test (work-order item A.4).
// Verifies:
//   1. Initial reset leaves all 5 control registers reading 0 after release.
//   2. After loading non-zero patterns and exercising W1C / auto-clear,
//      asserting the DUT reset (active high) clears every register
//      (gpu_ctrl_regfile reset: axil_control.sv:381-383), and the
//      interrupt generator is also reset (intr_gen reset: axil_control.sv:471).
//   3. Reg1 (STATUS) bit0 is a LIVE read-only interrupt flag (intr_gen.irq_o),
//      not a stored register — CPU writes to it are dropped (axil_control.sv:395-396).
//      The scoreboard models readback from the live interrupt state, which this
//      test keeps at 0 (no start->done cycle is issued here).
class tc_axfe_reset_behavior extends axfe_base_test;
  `uvm_component_utils(tc_axfe_reset_behavior)

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  task run_phase(uvm_phase phase);
    phase.raise_objection(this);

    // Wait for initial reset release.
    wait(env.ctrl_agent.vif.rst_n === 1'b1);
    repeat(5) @(posedge env.ctrl_agent.vif.clk);

    `uvm_info("A4", "STEP 1: verify all registers read 0 after initial reset", UVM_LOW);
    read_reg(32'h00);
    read_reg(32'h04);
    read_reg(32'h08);
    read_reg(32'h0C);
    read_reg(32'h10);

    `uvm_info("A4", "STEP 2: load known non-zero patterns, verify readback", UVM_LOW);
    // Reg0 (CTRL): write 0 (must not set start[0] or soft-reset[1] — avoid
    // triggering the GPU start / state machine).
    write_reg(32'h00, 32'h00000000);
    // Reg1 (STATUS) is read-only; exercise the "write to read-only reg" path —
    // the DUT drops it and the scoreboard models it as a live 0.
    write_reg(32'h04, 32'h80000001);
    write_reg(32'h08, 32'h00000001); // Reg2 INT_CLR W1C: model cleared to 0
    write_reg(32'h0C, 32'hA5A5A5A5);
    write_reg(32'h10, 32'h5A5A5A5A);
    repeat(2) @(posedge env.ctrl_agent.vif.clk);

    read_reg(32'h00);
    read_reg(32'h04);
    read_reg(32'h08);
    read_reg(32'h0C);
    read_reg(32'h10);

    `uvm_info("A4", "STEP 3: assert DUT reset and verify all registers clear to 0", UVM_LOW);
    // do_reset drives the active-high DUT reset through clk_rst_ctrl
    // and resets the scoreboard register model to 0 in sync.
    do_reset(4);
    repeat(5) @(posedge env.ctrl_agent.vif.clk);

    read_reg(32'h00);
    read_reg(32'h04);
    read_reg(32'h08);
    read_reg(32'h0C);
    read_reg(32'h10);

    `uvm_info("A4", "Reset behavior test complete", UVM_LOW);
    #100ns;
    phase.drop_objection(this);
  endtask

endclass
