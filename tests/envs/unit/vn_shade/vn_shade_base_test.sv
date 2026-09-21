`ifndef VN_SHADE_BASE_TEST_SV
`define VN_SHADE_BASE_TEST_SV

class vn_shade_base_test extends uvm_test;
  `uvm_component_utils(vn_shade_base_test)

  env_vn_shade env;

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    env = env_vn_shade::type_id::create("env", this);
  endfunction

  // Wait for reset release (DUT leaves its reset state; light phase begins).
  task wait_for_reset();
    wait(env.in_agent.vif.rst_n === 1'b1);
    repeat(10) @(posedge env.in_agent.vif.clk);
  endtask

  // Re-assert and release DUT reset through the clock/reset controller.
  task do_reset(int hold_cycles = 2);
    env.clk.apply_reset(hold_cycles);
  endtask

  // Start a new frame: reset the DUT, clear scoreboard state, wait for reset
  // release. Precondition: the previous stream must have fully drained
  // (call wait_drained() first) — reset_state() errors on pending entries.
  task new_frame(int hold_cycles = 2);
    do_reset(hold_cycles);
    env.scb.reset_state();
    wait_for_reset();
  endtask

  // Wait until the frame has fully drained on BOTH sides of the scoreboard:
  // all expected outputs captured (exp_q empty, no partial triplet) AND the
  // input-side parse quiesced (in_count unchanged for a few samples). The
  // input monitor observes the last accepted word a few cycles after the
  // DUT handshake, so the final exp entry is pushed AFTER the
  // second-to-last output has already popped — waiting on exp_q alone can
  // exit during that gap, and the frame-boundary reset then orphans the
  // last vertex's exp entry (reset_state() error) and kills its in-flight
  // output. Call after the last input word of the frame has been accepted;
  // required before new_frame().
  // Watchdog: a DUT that never emits (or under-emits) would otherwise hang
  // the test here — the input-side driver has its own accept timeout.
  task wait_drained();
    int unsigned watchdog = 10000;
    int unsigned quiet = 0;
    int unsigned last_in = env.scb.in_count;
    while (1) begin
      @(posedge env.in_agent.vif.clk);
      if ((env.scb.exp_q.size() == 0) && (env.scb.normal_word_idx == 0) &&
          (env.scb.in_count == last_in)) begin
        if (++quiet >= 3) return;
      end else begin
        quiet = 0;
      end
      last_in = env.scb.in_count;
      if (watchdog-- == 1)
        `uvm_fatal("WAIT_DRAINED", $sformatf("DUT did not drain the %0d pending expected output(s) within 10000 cycles", env.scb.exp_q.size()))
    end
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

  // Send the light preamble: three words (Lx, Ly, Lz), one accepted cycle
  // each, on env.in_agent.sqr.
  task send_light(logic signed [26:0] lx, logic signed [26:0] ly, logic signed [26:0] lz);
    vn_shade_light_seq seq = vn_shade_light_seq::type_id::create("seq");
    seq.lx = lx;
    seq.ly = ly;
    seq.lz = lz;
    seq.start(env.in_agent.sqr);
  endtask

  // Send one vertex normal: three words (nx, ny, nz), one accepted cycle
  // each, on env.in_agent.sqr.
  task send_normal(logic signed [26:0] nx, logic signed [26:0] ny, logic signed [26:0] nz);
    vn_shade_normal_seq seq = vn_shade_normal_seq::type_id::create("seq");
    seq.nx = nx;
    seq.ny = ny;
    seq.nz = nz;
    seq.start(env.in_agent.sqr);
  endtask

endclass

`endif
