`ifndef AXFE_BASE_TEST_SV
`define AXFE_BASE_TEST_SV

class axfe_base_test extends uvm_test;
  `uvm_component_utils(axfe_base_test)

  env_axfe env;
  virtual gpu_hs_if vif_gpu_hs;

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    env = env_axfe::type_id::create("env", this);
    if (!uvm_config_db#(virtual gpu_hs_if)::get(this, "", "vif", vif_gpu_hs))
      `uvm_warning("BTEST", "gpu_hs vif not set (gpu-handshake tests will be limited)")
  endfunction

  // Drive gpu_ctrl_done (DUT input). Single-driver: no gpu_hs agent is in the env.
  task set_done(logic d);
    if (vif_gpu_hs == null) `uvm_fatal("BTEST", "vif_gpu_hs not available")
    vif_gpu_hs.done <= d;
  endtask

  // Wait for a single gpu_start pulse (high then low) within max_cyc cycles.
  task wait_start_pulse(int max_cyc = 200);
    bit saw_hi = 1'b0;
    if (vif_gpu_hs == null) `uvm_fatal("BTEST", "vif_gpu_hs not available")
    repeat (max_cyc) begin
      @(vif_gpu_hs.mon_cb);
      if (vif_gpu_hs.mon_cb.start) begin saw_hi = 1'b1; break; end
    end
    if (!saw_hi) `uvm_error("BTEST", $sformatf("gpu_start never asserted within %0d cycles", max_cyc))
    repeat (max_cyc) begin
      @(vif_gpu_hs.mon_cb);
      if (!vif_gpu_hs.mon_cb.start) break;
    end
    if (vif_gpu_hs.mon_cb.start) `uvm_error("BTEST", "gpu_start did not deassert (expected a pulse)")
  endtask

  // Overwrite the scoreboard's cached register model (used to sync after DUT auto-clear).
  task sync_reg_model(int idx, logic [31:0] val);
    if (idx >= 0 && idx < 5) env.scb.regs[idx] = val;
    if (idx == 3) env.scb.dma_input_offset = val;
  endtask

  // Reset the scoreboard model to 0 post-reset
  task reset_scb_model();
    for (int i = 0; i < 5; i++) env.scb.regs[i] = 32'h0;
    env.scb.dma_input_offset = 32'h0;
    // intr_gen is reset by the DUT reset, so the live STATUS bit clears too.
    env.scb.status_gpu_done = 32'h0;
  endtask

  // Reflect the DUT's live STATUS bit0 (gpu_done interrupt) into the scoreboard
  // model. Called by tests after a start->done cycle sets the interrupt, or
  // after INT_CLR / reset clears it — mirroring intr_gen.irq_o.
  function void set_status_gpu_done(int v);
    if (v) env.scb.status_gpu_done = 32'h1;
    else   env.scb.status_gpu_done = 32'h0;
  endfunction

  task do_reset(int hold_cycles = 2);
    env.clk.apply_reset(hold_cycles);
    reset_scb_model();
  endtask

  task stop_clk();
    env.clk.stop_clk();
  endtask

  task resume_clk();
    env.clk.resume_clk();
  endtask

  function void set_clk_period_ns(real period_ns);
    env.clk.set_clk_period_ns(period_ns);
  endfunction

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

  task send_dma_req(logic [31:0] addr);
    axfe_dma_req_seq seq = axfe_dma_req_seq::type_id::create("seq");
    seq.addr = addr;
    seq.start(env.dma_req_agent.sqr);
  endtask

  task seed_memory(int num_words, logic [31:0] base_addr = 32'h0);
    for (int i = 0; i < num_words; i++) begin
      env.mem.write(base_addr + (i * 4), 32'h10000000 + i);
    end
  endtask

endclass

`endif
