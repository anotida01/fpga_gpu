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
    if (idx >= 0 && idx < 5) env.scb.rm[idx].stored = val;
  endtask

  // Reset the scoreboard model post-reset: clears stored regs AND the live
  // STATUS bit (intr_gen is reset by the DUT reset, so the interrupt clears).
  task reset_scb_model();
    env.scb.model_reset();
  endtask

  // --- Live STATUS (Reg1 bit0) event hooks -----------------------------------
  // The scoreboard mirrors the DUT's intr_gen.irq_o via explicit event hooks so
  // tests read like the RTL and don't carry DUT interrupt knowledge:
  //   report_gpu_done() : a start->done cycle has completed (interrupt latched)
  //   clear_gpu_done()  : INT_CLR W1C wrote the interrupt clear
  // Note: a Reg2 (INT_CLR) write already clears the model automatically inside
  // the scoreboard's write path; call clear_gpu_done() only to mirror a model
  // that did not already do so.

  function void report_gpu_done();
    env.scb.report_gpu_done();
  endfunction

  function void clear_gpu_done();
    env.scb.clear_gpu_done();
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
