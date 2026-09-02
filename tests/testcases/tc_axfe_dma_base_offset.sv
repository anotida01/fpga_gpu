`timescale 1ps/1ps
import uvm_pkg::*;
import axi4lite_pkg::*;
import pipe_pkg::*;
import gpu_hs_pkg::*;
import axfe_env_pkg::*;
import axfe_seq_pkg::*;
`include "uvm_macros.svh"

// ITEM 3B — DMA read at a non-zero IN_MEM_OFF (Reg3) base.
//
// Design intent (protocol/register-map level):
// Reg3 (offset 0x0C) is IN_MEM_OFF, the DMA read base offset. The DUT's DMA
// master should issue the read at (IN_MEM_OFF + req_word*4) per the register
// map. The scoreboard models byte_addr = req_word*4 + Reg3, so seeding the
// mem at (base + i*4) and running a 4-word burst from address 0..3 verifies
// the DUT applies the programmed base rather than ignoring Reg3.
//
// Two bases are exercised (0x0100 and 0x8000) to confirm the offset works at
// different magnitudes. Each word is scoreboard-checked against the seeded
// mem at (base + i*4).

class tc_axfe_dma_base_offset extends axfe_base_test;
  `uvm_component_utils(tc_axfe_dma_base_offset)

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  // Burst helper: writes Reg3 to the given base, seeds 4 words at (base+i*4)
  // with a distinguishable per-word pattern, then issues DMA reqs for
  // addresses 0..3. The scoreboard auto-derives expected byte addresses from
  // Reg3 and checks each response's data.
  task run_burst(logic [31:0] base);
    logic [31:0] data_base = 32'hA5A50000;

    write_reg(32'h0C, base);  // Reg3 IN_MEM_OFF

    for (int i = 0; i < 4; i++)
      env.mem.write(base + (i*4), data_base + i);

    for (int i = 0; i < 4; i++) begin
      send_dma_req(i[31:0]);
      `uvm_info("3B", $sformatf("OK: base 0x%0h word %0d DMA req completed (scoreboard-checked data)",
                                base, i), UVM_LOW)
    end
    repeat(5) @(posedge env.ctrl_agent.vif.clk);
  endtask

  task run_phase(uvm_phase phase);
    int c;
    phase.raise_objection(this);

    wait(env.ctrl_agent.vif.rst_n === 1'b1);
    repeat(5) @(posedge env.ctrl_agent.vif.clk);

    `uvm_info("3B", "DMA read at non-zero IN_MEM_OFF (Reg3) base: 0x0100 and 0x8000", UVM_LOW)

    // Two bursts × 4 words each.
    env.scb.expected_dma_rsp = 8;

    run_burst(32'h00000100);
    `uvm_info("3B", "OK: burst at base 0x00000100 complete", UVM_LOW)

    run_burst(32'h00008000);
    `uvm_info("3B", "OK: burst at base 0x00008000 complete", UVM_LOW)

    // Drain: send_dma_req returns at DUT-accept (not response-consumed), so the
    // last request's response is still in flight. Ensure all 8 are consumed
    // before check_phase. Bounded so the sim never hangs.
    c = 0;
    repeat (200) begin
      @(posedge env.ctrl_agent.vif.clk);
      if (env.scb.dma_rsp_count >= 8) begin c = 1; break; end
    end
    if (!c)
      `uvm_error("3B", $sformatf("Timed out draining DMA responses (dma_rsp_count = %0d, expected 8)", env.scb.dma_rsp_count))

    #100ns;
    phase.drop_objection(this);
  endtask

endclass
