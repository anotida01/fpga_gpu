`timescale 1ps/1ps
import uvm_pkg::*;
import axi4lite_pkg::*;
import pipe_pkg::*;
import axfe_env_pkg::*;
import axfe_seq_pkg::*;
`include "uvm_macros.svh"

// Basic AXI4-Lite front-end write/read smoke test.
// Verifies that the axil_gpu_front_end control slave and DMA master datapaths
// transfer data correctly:
//   1. Seeds the memory model with 4 known 32-bit words at addresses 0x0-0xC.
//   2. Issues 4 DMA read requests; the scoreboard checks the returned data
//      matches the seeded memory contents.
//   3. Writes 5 distinct patterns to control register offsets 0x0-0x10 and
//      reads them all back; the scoreboard verifies each readback equals the
//      last value written (register file R/W consistency).
class tc_axilfe_basic_wr_rd extends axfe_base_test;
  `uvm_component_utils(tc_axilfe_basic_wr_rd)

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  task run_phase(uvm_phase phase);
    phase.raise_objection(this);

    // Tell the scoreboard how many CTRL read and DMA response transactions to
    // expect before it declares the test complete.
    env.scb.expected_ctrl_rd = 5;
    env.scb.expected_dma_rsp = 4;

    // Wait for reset release and let the design settle after reset.
    wait(env.ctrl_agent.vif.rst_n === 1'b1);
    repeat(5) @(posedge env.ctrl_agent.vif.clk);

    // 1. Seed the memory model with 4 known patterns; the DMA read responses
    //    are checked against these values by the scoreboard.
    env.mem.write(32'h0, 32'habababab);
    env.mem.write(32'h4, 32'habcd1234);
    env.mem.write(32'h8, 32'h1234abcd);
    env.mem.write(32'hc, 32'hffffdddd);

    // 2. Drive 4 DMA read requests (one per seeded word) to exercise the DMA
    //    master read datapath.
    for (int i=0; i<4; i++) begin
      send_dma_req(i);
    end

    // 3. Write known patterns to all 5 control register offsets (CTRL, STATUS,
    //    INT_CLR, IN_MEM_OFF, OUT_MEM_OFF).
    write_reg(32'h0, 32'hdeadbeef);
    write_reg(32'h4, 32'h51515151);
    write_reg(32'h8, 32'ha5a5a5a5);
    write_reg(32'hc, 32'h1234abcd);
    write_reg(32'h10, 32'hffffdddd);

    // 4. Read all 5 registers back; the scoreboard compares each read data
    //    payload against the last write value for that offset.
    read_reg(32'h0);
    read_reg(32'h4);
    read_reg(32'h8);
    read_reg(32'hc);
    read_reg(32'h10);

    #100ns;
    phase.drop_objection(this);
  endtask

endclass
