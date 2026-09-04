`ifndef TC_ROP_BASIC_SV
`define TC_ROP_BASIC_SV
`timescale 1ps/1ps
import uvm_pkg::*;
import pipe_pkg::*;
import rop_env_pkg::*;
import rop_seq_pkg::*;
`include "uvm_macros.svh"

class tc_rop_basic extends rop_base_test;
  `uvm_component_utils(tc_rop_basic)

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  task run_phase(uvm_phase phase);
    phase.raise_objection(this);

    // Wait for reset release
    wait(env.in_agent.vif.rst_n === 1'b1);
    repeat(10) @(posedge env.in_agent.vif.clk);

    `uvm_info("TC_ROP", "Starting tc_rop_basic transactions...", UVM_LOW)

    // 1. Identity / trivial colors test
    begin
      rop_in_seq seq = rop_in_seq::type_id::create("seq");
      seq.c0 = 27'sd100; seq.c1 = 27'sd200; seq.c2 = 27'sd300;
      seq.w0 = 32'sd16384; seq.w1 = 32'sd0; seq.w2 = 32'sd0; // 1.0 weight on w0
      seq.x  = 32'd5;      seq.y  = 32'd10;
      seq.start(env.in_agent.sqr);
    end

    // 2. Uniform weights test
    begin
      rop_in_seq seq = rop_in_seq::type_id::create("seq");
      seq.c0 = 27'sd1000; seq.c1 = 27'sd1000; seq.c2 = 27'sd1000;
      seq.w0 = 32'sd5461; seq.w1 = 32'sd5461; seq.w2 = 32'sd5462; // approx 1/3 each
      seq.x  = 32'd320;   seq.y  = 32'd240;
      seq.start(env.in_agent.sqr);
    end

    // 3. Negative signed values test
    begin
      rop_in_seq seq = rop_in_seq::type_id::create("seq");
      seq.c0 = -27'sd500; seq.c1 = 27'sd1500; seq.c2 = -27'sd250;
      seq.w0 = 32'sd8192; seq.w1 = 32'sd4096; seq.w2 = 32'sd4096;
      seq.x  = 32'd100;   seq.y  = 32'd50;
      seq.start(env.in_agent.sqr);
    end

    // 4. Random sweep
    repeat (32) begin
      rop_in_seq seq = rop_in_seq::type_id::create("seq");
      assert(seq.randomize() with {
        c0 inside {[-10000:10000]};
        c1 inside {[-10000:10000]};
        c2 inside {[-10000:10000]};
        w0 inside {[-16384:32768]};
        w1 inside {[-16384:32768]};
        w2 inside {[-16384:32768]};
        x  inside {[0:639]};
        y  inside {[0:479]};
      });
      seq.start(env.in_agent.sqr);
    end

    #500ns;
    `uvm_info("TC_ROP", "Finished tc_rop_basic transactions.", UVM_LOW)
    phase.drop_objection(this);
  endtask

endclass

`endif
