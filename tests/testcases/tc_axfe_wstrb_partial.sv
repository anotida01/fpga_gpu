`timescale 1ps/1ps
import uvm_pkg::*;
import axi4lite_pkg::*;
import pipe_pkg::*;
import gpu_hs_pkg::*;
import axfe_env_pkg::*;
import axfe_seq_pkg::*;
`include "uvm_macros.svh"

// WSTRB partial-write test for the axil_ctrl_slave register file.
//
// DESIGN DEFICIENCY UNDER TEST: the DUT's gpu_ctrl_regfile (axil_control.sv,
// write path) performs a full 32-bit masked write and NEVER consults the
// write strobes (i_wb_sel / WSTRB). A partial write (strb != 4'hF) therefore
// silently overwrites the bytes the master did NOT strobe. This is illegal
// under AXI4-Lite (IHI 0022): a compliant slave MUST honor WSTRB byte-select.
//
// This test drives partial writes to Reg3 (IN_MEM_OFF, 0x0C) — a plain stored
// register with a full wmask and no FSM side-effects — and ASSERTS the intended
// byte-select contract. The scoreboard honors WSTRB (see axfe_scoreboard
// write_ctrl), so against the current DUT the two partial-write readbacks FAIL
// (the DUT returns the full overwritten word instead of preserving the
// non-strobed bytes). The test is therefore EXPECTED RED (2 UVM_ERROR, 0
// UVM_FATAL) until the DUT is fixed to honor WSTRB (design decision W6 / RTL
// work order). It is the verification gate that catches this deficiency.
//
// Per-step expectation (register 0x0C), DUT behavior (full-word write):
//   Step 1  baseline  write A5A5A5A5 strb=F  read -> A5A5A5A5  (PASS)
//   Step 2  byte0     write 00000011 strb=1  read expect A5A5A511 / DUT 00000011 (FAIL)
//   Step 3  byte3     write 11000000 strb=8  read expect 11A5A5A5 / DUT 11000000 (FAIL)
//   Step 4  cleanup   write 00000000 strb=F  read -> 00000000  (PASS)
class tc_axfe_wstrb_partial extends axfe_base_test;
  `uvm_component_utils(tc_axfe_wstrb_partial)

  localparam logic [31:0] REG_IN_MEM_OFF = 32'h0C; // Reg3, IN_MEM_OFF, full wmask
  localparam logic [31:0] PATTERN        = 32'hA5A5A5A5;

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  // Re-baseline: write a known full-word value to Reg3 and read it back. A
  // full-word write is honored by both the DUT and the scoreboard, so this
  // round-trip passes and gives each partial step a clean, independent basis.
  task baseline();
    write_reg(REG_IN_MEM_OFF, PATTERN, 4'hF);
    read_reg(REG_IN_MEM_OFF);
  endtask

  task run_phase(uvm_phase phase);
    phase.raise_objection(this);

    // Wait for reset release and let the design settle after reset.
    wait(env.ctrl_agent.vif.rst_n === 1'b1);
    repeat(5) @(posedge env.ctrl_agent.vif.clk);

    `uvm_info("TEST", "Starting WSTRB partial-write test", UVM_LOW)

    // --- Step 1: baseline full-word write/read (PASS) ------------------------
    baseline();
    `uvm_info("TEST", "Step 1 (baseline full-word) readback checked", UVM_LOW)

    // --- Step 2: partial write, LSByte only (EXPECTED FAIL vs current DUT) ---
    baseline();
    write_reg(REG_IN_MEM_OFF, 32'h00000011, 4'h1); // strb=1: only byte0
    read_reg(REG_IN_MEM_OFF);
    // Intended (scoreboard):  A5A5A511  (byte0=0x11, bytes1-3 preserved)
    // Current DUT (full-word): 00000011  -> UVM_ERROR, this is the deficiency.
    `uvm_info("TEST", "Step 2 (byte0 partial write) readback checked", UVM_LOW)

    // --- Step 3: partial write, HSByte only (EXPECTED FAIL vs current DUT) ---
    baseline();
    write_reg(REG_IN_MEM_OFF, 32'h11000000, 4'h8); // strb=8: only byte3
    read_reg(REG_IN_MEM_OFF);
    // Intended (scoreboard):  11A5A5A5  (byte3=0x11, bytes0-2 preserved)
    // Current DUT (full-word): 0x11000000  -> UVM_ERROR, this is the deficiency.
    `uvm_info("TEST", "Step 3 (byte3 partial write) readback checked", UVM_LOW)

    // --- Step 4: cleanup — reset Reg3 to a known value (PASS) -----------------
    write_reg(REG_IN_MEM_OFF, 32'h00000000, 4'hF);
    read_reg(REG_IN_MEM_OFF);

    `uvm_info("TEST", "WSTRB partial-write test complete", UVM_LOW)
    #100ns;
    phase.drop_objection(this);
  endtask

endclass
