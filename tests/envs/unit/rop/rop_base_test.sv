`ifndef ROP_BASE_TEST_SV
`define ROP_BASE_TEST_SV

class rop_base_test extends uvm_test;
  `uvm_component_utils(rop_base_test)

  env_rop env;

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    env = env_rop::type_id::create("env", this);
  endfunction

  // Re-assert and release DUT reset through the clock/reset controller.
  task do_reset(int hold_cycles = 2);
    env.clk.apply_reset(hold_cycles);
  endtask

  // Stop generating the DUT clock.
  task stop_clk();
    env.clk.stop_clk();
  endtask

  // Resume DUT clock generation.
  task resume_clk();
    env.clk.resume_clk();
  endtask

  // Set the DUT clock period (nanoseconds).
  function void set_clk_period_ns(real period_ns);
    env.clk.set_clk_period_ns(period_ns);
  endfunction

  // Convenience driver: issue one input transaction through the input sequencer.
  task send_input(logic signed [26:0] c0, logic signed [26:0] c1, logic signed [26:0] c2,
                  logic signed [31:0] w0, logic signed [31:0] w1, logic signed [31:0] w2,
                  logic [31:0] x, logic [31:0] y);
    rop_in_seq seq = rop_in_seq::type_id::create("seq");
    seq.c0 = c0;  seq.c1 = c1;  seq.c2 = c2;
    seq.w0 = w0;  seq.w1 = w1;  seq.w2 = w2;
    seq.x  = x;   seq.y  = y;
    seq.start(env.in_agent.sqr);
  endtask

endclass

`endif
