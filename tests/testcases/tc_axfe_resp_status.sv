`timescale 1ps/1ps
import uvm_pkg::*;
import axi4lite_pkg::*;
import pipe_pkg::*;
import gpu_hs_pkg::*;
import axfe_env_pkg::*;
import axfe_seq_pkg::*;
`include "uvm_macros.svh"

// AXI RESPONSE-STATUS test (WORK_axfe_resp_status.md item 3).
// Narrow test: it verifies the *response status* the DUT returns on CTRL
// accesses (bresp on writes, rresp on reads), enforced by the scoreboard from
// items 1+2 -- it does NOT re-test register semantics (that is regmap_corner):
//   1. In-range OKAY sweep: write+read each of Reg0..Reg4 (offsets 0x00/0x04/
//      0x08/0x0C/0x10). The scoreboard enforces bresp/rresp == OKAY (item 1)
//      and checks the readback data (the live Reg1 / W1C Reg2 hooks below
//      keep the model consistent, as in tc_axfe_intr_status_lifecycle).
//   2. OOR capture: write+read at 0x14 and 0x1C. With en_oob_resp==0 (default)
//      these stay green (data==0 only) while the scoreboard logs the observed
//      OOR response (item 2). The DUT was observed returning OKAY (00) + read-0
//      for every OOR access -- permissive decode; see item 2 Notes / W6.
class tc_axfe_resp_status extends axfe_base_test;
  `uvm_component_utils(tc_axfe_resp_status)

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  task run_phase(uvm_phase phase);
    phase.raise_objection(this);

    // Wait for reset release and let the design settle.
    wait(env.ctrl_agent.vif.rst_n === 1'b1);
    repeat(5) @(posedge env.ctrl_agent.vif.clk);

    `uvm_info("TEST", "Starting AXI response-status test", UVM_LOW)

    // Leave the live STATUS (Reg1) and W1C INT_CLR (Reg2) clean so the in-range
    // sweep's data checks are deterministic: no pending interrupt to clear, no
    // stale stored bits. Mirrors the hook usage in tc_axfe_intr_status_lifecycle.
    clear_gpu_done();
    write_reg(32'h08, 32'h1);   // INT_CLR W1C self-clear -> Reg2 reads 0
    read_reg (32'h08);          // expect 0 (W1C cleared)
    read_reg (32'h04);          // Reg1 live STATUS, intr not latched -> expect 0

    // OOR capture (item 2). en_oob_resp==0 (default): data==0 is enforced and
    // the observed bresp/rresp is only reported. The DUT returns OKAY(00) +
    // read-0 here (permissive decode) -- the scoreboard logs it for W6.
    write_reg(32'h14, 32'hdeadbeef);
    write_reg(32'h1c, 32'h12345678);
    read_reg (32'h14);
    read_reg (32'h1c);

    // In-range OKAY sweep (item 1): write+read each defined register; the
    // scoreboard enforces bresp/rresp == OKAY on every one and checks data.
    // Reg1 (0x04, live): reads back the (unlatched) interrupt -> 0.
    // Reg2 (0x08, W1C): cleared by the W1C write above -> reads 0.
    // Reg0 (0x00) / Reg4 (0x10): stored -> read back the written value.
    write_reg(32'h00, 32'h12345678);
    write_reg(32'h04, 32'h51515151);  // live: dropped by DUT, readback stays 0
    write_reg(32'h08, 32'h00000001);  // W1C: clears interrupt + self-clears
    read_reg (32'h04);                // live Reg1, expect 0
    write_reg(32'h0C, 32'h87654321);
    write_reg(32'h10, 32'haaaa5555);
    read_reg (32'h00);                // stored, expect 0x12345678
    read_reg (32'h08);                // W1C cleared, expect 0
    read_reg (32'h0C);                // stored, expect 0x87654321
    read_reg (32'h10);                // stored, expect 0xaaaa5555

    `uvm_info("TEST", "Response-status test complete (scoreboard enforced OKAY + data)", UVM_LOW)
    #100ns;
    phase.drop_objection(this);
  endtask

endclass
