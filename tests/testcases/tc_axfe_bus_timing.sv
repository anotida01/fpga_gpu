`timescale 1ps/1ps
import uvm_pkg::*;
import axi4lite_pkg::*;
import pipe_pkg::*;
import gpu_hs_pkg::*;
import axfe_env_pkg::*;
import axfe_seq_pkg::*;
`include "uvm_macros.svh"

// Bus / timing corner-case test for the AXI4-Lite write path on the CTRL port
// (work order items 4A/4B).
//
// The DUT's AXI slave is the third-party bridge `axlite2wbsp`
// (submodules/wb2axip/rtl/axlite2wbsp.v). Internally the write channel is
// decoded by `axilwr2wbsp`, which latches the AW and W channels INDEPENDENTLY:
//   - When AW is latched but W has not yet arrived, `o_axi_awready` drops to 0
//     ("if the write address is given without any corresponding write data,
//     stall and wait for the write data" -- axilwr2wbsp.v).
//   - Symmetrically, an early W drops `o_axi_wready` until AW arrives.
//   - The underlying Wishbone write fires only when BOTH pending channels are
//     latched (`pending_axi_write`), and exactly once.
//
// The pre-existing AXFE tests all assert AW and W on the same cycle (via
// `write_reg`), so the decoupled-arrival path is unexercised. This test
// drives AW/W in three orderings, each with a 4-write burst, and proves the
// DUT completes each write exactly once with the correct register value:
//   4A  AW_FIRST (address latched, data arrives later)
//   4B  W_FIRST  (data latched, address arrives later)
//   4C  AW_FIRST with a long 50-cycle gap (extended stall)
//
// "Exactly once + correct data" is proven by the scoreboard's per-register
// model (axfe_scoreboard.sv): each WRITE updates the model exactly once and
// each READ is compared against the expected model value. A double-fired or
// mis-ordered handshake would either corrupt the readback data or fire the
// wrong register, both of which the scoreboard flags. Exactly 12 reads are
// expected (3 sub-tests x 4 reads each).
class tc_axfe_bus_timing extends axfe_base_test;
  `uvm_component_utils(tc_axfe_bus_timing)

  localparam logic [31:0] ADDR_REG3 = 32'h0C;
  localparam logic [31:0] ADDR_REG4 = 32'h10;
  localparam logic [31:0] ADDR_REG0 = 32'h00;
  localparam logic [31:0] ADDR_REG1 = 32'h04;

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  // Drive a 4-write burst (Reg3, Reg4, Reg0, Reg1) in the given aw_w_mode /
  // gap, each followed by a scoreboard-checked readback. `tag` is just for
  // log readability.
  task sub_test(aw_w_mode_e mode, int unsigned gap, string tag);
    `uvm_info("4", $sformatf("%s: AW/W re-ordering, gap=%0d cycles (4 writes + reads)", tag, gap), UVM_LOW)
    write_reg_seq(ADDR_REG3, 32'hAAAA0000 + gap, mode, gap);
    read_reg(ADDR_REG3);
    write_reg_seq(ADDR_REG4, 32'h55550000 + gap, mode, gap);
    read_reg(ADDR_REG4);
    write_reg_seq(ADDR_REG0, 32'h80000000, mode, gap);
    read_reg(ADDR_REG0);
    write_reg_seq(ADDR_REG1, 32'h80000001, mode, gap);
    read_reg(ADDR_REG1);
    `uvm_info("4", $sformatf("OK: %s 4 writes landed exactly once (gap=%0d cycles)", tag, gap), UVM_LOW)
  endtask

  task run_phase(uvm_phase phase);
    phase.raise_objection(this);

    env.scb.model_reset();
    env.scb.expected_ctrl_rd = 12; // 3 sub-tests x 4 reads

    wait(env.ctrl_agent.vif.rst_n === 1'b1);
    repeat(5) @(posedge env.ctrl_agent.vif.clk);

    `uvm_info("4", "bus/timing corner test: AW/W re-ordering on the CTRL path", UVM_LOW)

    sub_test(AW_FIRST, 5,  "4A");
    sub_test(W_FIRST,  5,  "4B");
    sub_test(AW_FIRST, 50, "4C");

    `uvm_info("4", "OK: all sub-tests complete; DUT accepted each AW/W write exactly once", UVM_LOW)

    #100ns;
    phase.drop_objection(this);
  endtask

endclass
