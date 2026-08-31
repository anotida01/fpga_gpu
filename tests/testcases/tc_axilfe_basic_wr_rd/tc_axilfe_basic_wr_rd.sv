`timescale 1ps/1ps
import uvm_pkg::*;
import axi4lite_pkg::*;
import pipe_pkg::*;
import axfe_env_pkg::*;
import axfe_seq_pkg::*;
`include "uvm_macros.svh"

class tc_axilfe_basic_wr_rd extends uvm_test;
  `uvm_component_utils(tc_axilfe_basic_wr_rd)

  env_axfe env;

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    env = env_axfe::type_id::create("env", this);
  endfunction

  task run_phase(uvm_phase phase);
    phase.raise_objection(this);

    // Wait for reset release
    wait(env.ctrl_agent.vif.rst_n === 1'b1);
    repeat(5) @(posedge env.ctrl_agent.vif.clk);

    // 1. Seed Memory Model
    env.mem.write(32'h0, 32'habababab);
    env.mem.write(32'h4, 32'habcd1234);
    env.mem.write(32'h8, 32'h1234abcd);
    env.mem.write(32'hc, 32'hffffdddd);

    // 2. DMA Requests (4 words)
    for (int i=0; i<4; i++) begin
      axfe_dma_req_seq seq = axfe_dma_req_seq::type_id::create("seq");
      seq.addr = i;
      seq.start(env.dma_req_agent.sqr);
    end

    // 3. CTRL Writes
    write_reg(32'h0, 32'hdeadbeef);
    write_reg(32'h4, 32'h51515151);
    write_reg(32'h8, 32'ha5a5a5a5);
    write_reg(32'hc, 32'h1234abcd);
    write_reg(32'h10, 32'hffffdddd);

    // 4. CTRL Reads
    read_reg(32'h0);
    read_reg(32'h4);
    read_reg(32'h8);
    read_reg(32'hc);
    read_reg(32'h10);

    #100ns;
    phase.drop_objection(this);
  endtask

  task write_reg(logic [31:0] addr, logic [31:0] data);
    axfe_axil_write_seq seq = axfe_axil_write_seq::type_id::create("seq");
    seq.addr = addr;
    seq.data = data;
    seq.start(env.ctrl_agent.sqr);
  endtask

  task read_reg(logic [31:0] addr);
    axfe_axil_read_seq seq = axfe_axil_read_seq::type_id::create("seq");
    seq.addr = addr;
    seq.start(env.ctrl_agent.sqr);
  endtask

endclass
