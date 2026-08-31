`timescale 1ps/1ps
import uvm_pkg::*;
import axi4lite_pkg::*;
import pipe_pkg::*;
import gpu_hs_pkg::*;
import axfe_env_pkg::*;
import axfe_seq_pkg::*;
`include "uvm_macros.svh"

// Register-map corner-case test for the axil_ctrl_slave register file.
// Exercises the register access semantics that differ from plain R/W:
//   1. Illegal offsets beyond the 5-register map (0x14, 0x1C): the slave must
//      respond with a legal AXI4-Lite transaction (no hang, no X propagation)
//      and not corrupt in-range registers.
//   2. STATUS (Reg1, 0x04) read-only masking: only bit0 (gpu_done) is
//      meaningful, so writing 0x80000001 must leave non-status bits masked
//      per the register mask on readback.
//   3. INT_CLR (Reg2, 0x08) write-1-clear semantics: writing 1 to bit0 clears
//      the interrupt and the bit self-clears, so a subsequent readback
//      returns the cleared value.
//   4. IN_MEM_OFF (Reg3, 0x0C) DMA base-address offset: verify a normal
//      write/read round-trip of the memory offset field.
// Behavior is verified by the axfe scoreboard comparing readback data against
// the expected register-model values.
class tc_axilfe_regmap_corner extends axfe_base_test;
  `uvm_component_utils(tc_axilfe_regmap_corner)

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  task run_phase(uvm_phase phase);
    phase.raise_objection(this);

    // Wait for reset release
    wait(env.ctrl_agent.vif.rst_n === 1'b1);
    repeat(5) @(posedge env.ctrl_agent.vif.clk);

    `uvm_info("TEST", "Starting register-map corner case tests", UVM_LOW)

    // 1. Illegal register offsets: access addresses beyond the 5-register map
    //    (registers end at offset 0x10). The slave must still complete the
    //    AXI transactions cleanly and not disturb in-range registers.
    write_reg(32'h14, 32'hdeadbeef);
    write_reg(32'h1c, 32'h12345678);
    read_reg(32'h14);
    read_reg(32'h1c);

    // 2. STATUS read-only mask: Reg1 (0x04) exposes only bit0 (gpu_done).
    //    Write a pattern with non-status bits set (0x80000001); the readback
    //    should reflect only the writable/meaningful portion per the DUT mask.
    write_reg(32'h04, 32'h80000001);
    read_reg(32'h04);

    // 3. INT_CLR write-1-clear: writing 1 to bit0 (clr_gpu_done) clears the
    //    done interrupt; the W1C nature means the bit reads back cleared.
    write_reg(32'h08, 32'h00000001);
    read_reg(32'h08);

    // 4. IN_MEM_OFF round-trip: write a non-zero DMA input memory base offset
    //    (0x0C) and read it back to confirm the offset field is stored intact.
    write_reg(32'h0C, 32'h12345678);
    read_reg(32'h0C);

    #100ns;
    phase.drop_objection(this);
  endtask

endclass
