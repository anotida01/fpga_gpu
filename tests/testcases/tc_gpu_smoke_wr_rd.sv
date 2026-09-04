`timescale 1ps/1ps
// Smoke test for the system env (env_gpu / axil_sys_top).
//
// Purpose: prove the end-to-end host path works through the DUT and crossbar —
// a plain R/W control register can be written and read back with the expected
// value -- WITHOUT launching a render (CONTROL[0]/start is deliberately not
// written, since a frame on unseeded RAM is out of scope for a smoke test).
//
// Checked by the scoreboard (gpu_scoreboard::handle_ctrl), not by test-side
// compare: write->read goes AW/W/B then AR/R; the monitor emits items that the
// scoreboard models (stored R/W register) and matches on readback. If the DUT or
// crossbar decode is wrong the scoreboard raises a UVM_ERROR.
import uvm_pkg::*;
import axi4lite_pkg::*;
import clk_rst_pkg::*;
import gpu_env_pkg::*;
import gpu_seq_pkg::*; // provides gpu_base_test
`include "uvm_macros.svh"

class tc_gpu_smoke_wr_rd extends gpu_base_test;
  `uvm_component_utils(tc_gpu_smoke_wr_rd)

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  task run_phase(uvm_phase phase);
    // Opt the scoreboard into exact counts: 5 reads + 2 writes (see sequence below).
    env.scb.expected_ctrl_rd = 5;
    env.scb.expected_ctrl_wr = 2;

    phase.raise_objection(this);

    // Let the shared reset controller release reset.
    wait(env.host_agent.vif.rst_n === 1'b1);
    repeat(5) @(posedge env.host_agent.vif.clk);

    // 1) Reset-state readback: the plain R/W registers and the live STATUS should
    //    all read 0 after reset (CONTROL/INT_CLR stored=0, STATUS live bit0=0).
    read_ctrl(REG_CONTROL);
    read_ctrl(REG_STATUS);

    // 2) Write/read a R/W register (IN_MEM_OFF) with a distinct pattern.
    write_ctrl(REG_IN_MEM_OFF, 32'hDEAD_BEEF);
    read_ctrl(REG_IN_MEM_OFF);

    // 3) ...and a second R/W register (OUT_MEM_OFF) with another pattern, to
    //    confirm independent storage.
    write_ctrl(REG_OUT_MEM_OFF, 32'h1234_5678);
    read_ctrl(REG_OUT_MEM_OFF);

    // 4) Re-read IN_MEM_OFF to confirm the OUT_MEM_OFF write did not disturb it.
    read_ctrl(REG_IN_MEM_OFF);

    #100ns;
    phase.drop_objection(this);
  endtask
endclass
