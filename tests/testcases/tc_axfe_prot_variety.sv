`timescale 1ps/1ps
import uvm_pkg::*;
import axi4lite_pkg::*;
import pipe_pkg::*;
import gpu_hs_pkg::*;
import axfe_env_pkg::*;
import axfe_seq_pkg::*;
`include "uvm_macros.svh"

// AXI4-Lite `prot` field variety test (work order item 2).
//
// COMPLIANCE CHECK: AXI4-Lite (IHI 0022/0028) defines a 3-bit `prot` field
// (awprot/arprot) that a master MAY use to indicate the transaction's
// privilege and security attributes. A compliant slave is required to complete
// every in-range access regardless of its `prot` value, returning OKAY. This
// DUT forwards `prot` through the axlite2wbsp bridge (i_axi_awprot /
// i_axi_arprot, axil.sv:120,131) but neither `bus_sm` nor `gpu_ctrl_regfile`
// consumes it for any gating — so the expected behavior is: for EVERY legal
// `prot` value the write completes with OKAY and the read returns OKAY with the
// correct data, with no hang and no SLVERR.
//
// This test sweeps all 8 `prot` values {0..7}. For each one it writes
// 0xCAFE0000 | prot[2:0] to Reg3 (IN_MEM_OFF, 0x0C) with that `prot`, then
// reads Reg3 back with the same `prot`. The lower 3 bits of the data encode
// the `prot` value, so the expected readback is distinct per step and the
// scoreboard's data-match catches any corruption or cross-contamination.
//
// OKAY is asserted on BOTH the write path (axfe_scoreboard write_ctrl,
// in-range resp check) and the read path (axfe_scoreboard, in-range resp check);
// data-match is asserted on the read. The driver also completes the B-channel
// handshake, so a write hang would surface as a sim timeout rather than a pass.
//
// Expected result: GREEN (8 prot values: write OKAY + read OKAY + correct
// data; no UVM_ERROR, no hang). If any `prot` causes SLVERR or a hang, that is
// a genuine DUT defect to flag.
class tc_axfe_prot_variety extends axfe_base_test;
  `uvm_component_utils(tc_axfe_prot_variety)

  localparam logic [31:0] REG_IN_MEM_OFF = 32'h0C; // Reg3, IN_MEM_OFF, full wmask
  localparam logic [31:0] DATA_BASE      = 32'hCAFE0000; // encodes prot in low 3 bits

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  task run_phase(uvm_phase phase);
    phase.raise_objection(this);

    env.scb.expected_ctrl_rd = 8; // 8 sweep reads

    wait(env.ctrl_agent.vif.rst_n === 1'b1);
    repeat(5) @(posedge env.ctrl_agent.vif.clk);

    `uvm_info("TEST", "Starting AXI4-Lite prot variety test (awprot/arprot 0..7)", UVM_LOW)

    for (int prot = 0; prot <= 7; prot++) begin
      write_reg(REG_IN_MEM_OFF, DATA_BASE | prot, 4'hF, prot);
      read_reg(REG_IN_MEM_OFF, prot);
    end

    `uvm_info("TEST", "prot sweep complete (all 8 values: OKAY + data match)", UVM_LOW)
    #100ns;
    phase.drop_objection(this);
  endtask

endclass