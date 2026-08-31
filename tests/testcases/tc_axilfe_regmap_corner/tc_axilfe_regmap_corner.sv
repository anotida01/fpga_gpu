`timescale 1ps/1ps
import uvm_pkg::*;
import axi4lite_pkg::*;
import pipe_pkg::*;
import gpu_hs_pkg::*;
import axfe_env_pkg::*;
import axfe_seq_pkg::*;
`include "uvm_macros.svh"

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

    // 1. Illegal register offset: read/write beyond reg 4 (e.g. 0x14, 0x1C)
    write_reg(32'h14, 32'hdeadbeef);
    write_reg(32'h1c, 32'h12345678);
    read_reg(32'h14);
    read_reg(32'h1c);

    // 2. STATUS read-only mask: Reg1 (0x04) has mask 32'h1. Write non-status bits (0x80000000)
    write_reg(32'h04, 32'h80000001);
    read_reg(32'h04);

    // 3. INT_CLR self-clear / W1C: write Reg2 (0x08), confirm it self-clears on readback
    write_reg(32'h08, 32'h00000001);
    read_reg(32'h08);

    // 4. RESET behavior: check that we can write non-zero and then read back
    write_reg(32'h0C, 32'h12345678);
    read_reg(32'h0C);

    #100ns;
    phase.drop_objection(this);
  endtask

endclass
