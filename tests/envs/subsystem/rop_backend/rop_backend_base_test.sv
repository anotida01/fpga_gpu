`ifndef ROP_BACKEND_BASE_TEST_SV
`define ROP_BACKEND_BASE_TEST_SV

class rop_backend_base_test extends uvm_test;
  `uvm_component_utils(rop_backend_base_test)

  env_rop_backend env;

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  // Mirror of the tb's +MEM_OFFSET plusarg (the DUT's output_mem_offset_addr_i
  // binding). Default 0.
  function logic [31:0] get_mem_offset();
    logic [31:0] v = 32'h0;
    if (!$value$plusargs("MEM_OFFSET=%d", v))
      v = 32'h0;
    return v;
  endfunction

  function void build_phase(uvm_phase phase);
    env = env_rop_backend::type_id::create("env", this);
  endfunction

  // build is top-down: env.scb does not exist yet during this test's
  // build_phase, so the cross-component hookup happens in connect_phase
  // (all components are built by then; same pattern as env_axfe's
  // s_drv.mem_model hookup).
  function void connect_phase(uvm_phase phase);
    env.scb.mem_offset = get_mem_offset();
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

  // Convenience driver: one pixel through the input sequencer (fixed point,
  // 14 fractional bits; the test is responsible for any pixel->domain math).
  task send_px(logic [31:0] x_i, logic [31:0] y_i, logic signed [31:0] c_i);
    rop_backend_px_seq seq = rop_backend_px_seq::type_id::create("seq");
    seq.x_i = x_i;
    seq.y_i = y_i;
    seq.c_i = c_i;
    seq.start(env.in_agent.sqr);
  endtask

  // Convenience driver: a random pixel stream (n pixels, screen-range).
  task send_stream(int unsigned n = 32, int unsigned gap_max = 4);
    rop_backend_stream_seq seq = rop_backend_stream_seq::type_id::create("seq");
    seq.n       = n;
    seq.gap_max = gap_max;
    seq.start(env.in_agent.sqr);
  endtask

  // Wait until the scoreboard has consumed every queued expected write
  // (all DUT writes matched), with a timeout so a stuck DUT fails loudly.
  task wait_drain(int unsigned timeout_cycles = 100_000);
    int unsigned waited = 0;
    while (env.scb.exp_q.size() > 0) begin
      @(env.in_agent.vif.mon_cb);
      waited++;
      if (waited >= timeout_cycles)
        `uvm_error("BASE_T", $sformatf(
          "wait_drain timed out after %0d cycles (%0d expected writes still queued)",
          waited, env.scb.exp_q.size()))
    end
  endtask

endclass

`endif
