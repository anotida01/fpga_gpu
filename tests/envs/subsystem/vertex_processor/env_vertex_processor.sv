`ifndef ENV_VERTEX_PROCESSOR_SV
`define ENV_VERTEX_PROCESSOR_SV

`uvm_analysis_imp_decl(_req)

// DMA response driver: request-driven.
//
// The DUT raises one-cycle gpu_valid_o request pulses, and only samples
// dma_valid_i while in WAIT_DMA. A stock fire-and-forget driver would race
// those windows and lose words. This driver instead waits for each DUT
// request (observed by the dma_req monitor and fed in through req_imp),
// pulls the matching sequence item, and drives data/valid until the DUT's
// gpu_ready_o accept pulse. It also checks that DUT request addresses
// arrive in strict 0,1,2,... order per frame.
//
// Response latency: the driver waits rsp_delay_cyc (default 2) cycles
// after each request before driving dma_valid_i, modeling a DMA front-end
// that needs a cycle or two to respond. It also keeps the response outside
// the DUT's return_state settling window — with the old vertex_processor
// state_logic (see the comment in rtl/vertex_processor/vertex_processor.sv),
// a response inside that window returned the SM to IDLE/RESET and aborted
// the frame; set rsp_delay_cyc to 0/1 against the old DUT to reproduce.
//
// Accept: the DUT latches the presented word in WAIT_DMA and asserts
// gpu_ready_o on the cycle it forwards the latched word to the unit, so
// the driver holds valid/data until that ready pulse — and one more cycle
// after it, so the monitor (which samples 1ns after the edge) observes the
// valid/ready handshake before valid deasserts.

class vp_dma_rsp_driver extends uvm_driver #(pipe_item);

  virtual pipe_if #(.DATA_W(32)) vif;
  uvm_analysis_imp_req #(pipe_item, vp_dma_rsp_driver) req_imp;

  bit frame_active = 0;
  int unsigned exp_addr = 0;
  // Cycles between seeing a request and driving dma_valid_i (see the
  // response-latency note in the header comment).
  int unsigned rsp_delay_cyc = 2;

  protected pipe_item req_q[$];

  localparam int unsigned TIMEOUT_CYC = 200_000;

  `uvm_component_utils(vp_dma_rsp_driver)

  function new(string name, uvm_component parent);
    super.new(name, parent);
    req_imp = new("req_imp", this);
  endfunction

  // Tests may override the front-end response latency:
  //   uvm_config_db#(int unsigned)::set(this, "env.dma_rsp_agent.drv",
  //                                     "rsp_delay_cyc", 0);
  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    if (uvm_config_db#(int unsigned)::get(this, "", "rsp_delay_cyc", rsp_delay_cyc))
      `uvm_info("DMA_RSP_DRV", $sformatf("rsp_delay_cyc overridden to %0d", rsp_delay_cyc), UVM_MEDIUM)
  endfunction

  // Fed by the dma_req monitor (the DUT's request channel).
  virtual function void write_req(pipe_item item);
    req_q.push_back(item);
  endfunction

  // Test hooks: bracket a frame so the driver can validate the request
  // address sequence and flag requests raised outside an active frame.
  task frame_start();
    exp_addr = 0;
    while (req_q.size() != 0) req_q.pop_front();
    frame_active = 1;
  endtask

  task frame_end();
    frame_active = 0;
  endtask

  task run_phase(uvm_phase phase);
    pipe_item req;
    pipe_item rsp;

    wait (vif.rst_n === 1'b1);
    vif.valid <= 1'b0;
    vif.addr  <= '0;
    vif.data  <= '0;

    forever begin
      // Wait for the DUT to raise a DMA request.
      wait (req_q.size() != 0);
      req = req_q.pop_front();
      if (!frame_active)
        `uvm_error("DMA_RSP_DRV", $sformatf("DUT DMA request (addr=%0d) outside an active frame", req.addr))
      if (req.addr != exp_addr)
        `uvm_error("DMA_RSP_DRV", $sformatf("DUT DMA request addr=%0d, expected %0d (request address sequence violation)", req.addr, exp_addr))
      exp_addr++;

      // Pull the next item from the sequence (the test paces the frame).
      fork
        seq_item_port.get_next_item(rsp);
        begin
          repeat (TIMEOUT_CYC) @(posedge vif.clk);
          `uvm_fatal("DMA_RSP_DRV", "timeout waiting for sequence item after DUT DMA request")
        end
      join_any
      disable fork;

      // Drive the 32-bit word after the front-end response latency; hold
      // until the DUT accepts (gpu_ready_o on the forward cycle), plus one
      // cycle so the monitor captures the valid/ready handshake.
      fork
        begin
          repeat (rsp_delay_cyc) @(posedge vif.clk);
          vif.data  <= rsp.data[31:0];
          vif.valid <= 1'b1;
          `uvm_info(get_type_name(),
            $sformatf("TRACE present : word addr=%0d data=0x%08h @ %0t (rsp_delay=%0d)",
                      req.addr, rsp.data[31:0], $time, rsp_delay_cyc),
            UVM_LOW)
          do @(posedge vif.clk); while (vif.ready !== 1'b1);
          `uvm_info(get_type_name(),
            $sformatf("TRACE accept  : word addr=%0d data=0x%08h @ %0t",
                      req.addr, rsp.data[31:0], $time),
            UVM_LOW)
          @(posedge vif.clk);
          vif.valid <= 1'b0;
        end
        begin
          repeat (TIMEOUT_CYC) @(posedge vif.clk);
          `uvm_fatal(get_type_name(),
            $sformatf("timeout waiting for DUT to accept DMA data for word addr=%0d @ %0t (DUT may not have entered WAIT_DMA)",
                      req.addr, $time))
        end
      join_any
      disable fork;

      seq_item_port.item_done();
    end
  endtask

endclass

// Response-side DMA agent: monitor + request-driven driver + sequencer.
class vp_dma_rsp_agent extends uvm_agent;
  pipe_monitor #(.DATA_W(32)) mon;
  vp_dma_rsp_driver           drv;
  pipe_sequencer              sqr;
  virtual pipe_if #(.DATA_W(32)) vif;

  `uvm_component_utils(vp_dma_rsp_agent)

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    if (!uvm_config_db#(virtual pipe_if #(.DATA_W(32)))::get(this, "", "vif", vif))
      `uvm_fatal("VIF", "No vif for vp_dma_rsp_agent")
    mon = pipe_monitor#(.DATA_W(32))::type_id::create("mon", this);
    drv = vp_dma_rsp_driver::type_id::create("drv", this);
    sqr = pipe_sequencer::type_id::create("sqr", this);
    mon.vif = vif;
    drv.vif = vif;
  endfunction

  function void connect_phase(uvm_phase phase);
    super.connect_phase(phase);
    drv.seq_item_port.connect(sqr.seq_item_export);
  endfunction

endclass

class env_vertex_processor extends uvm_env;
  pipe_agent #(.DATA_W(32))  dma_req_agent; // TB responder: drives dma_ready_i
  vp_dma_rsp_agent           dma_rsp_agent; // TB source:    drives dma_valid_i / dma_data_i
  pipe_agent #(.DATA_W(108)) vout_agent;    // TB sink:      consumes vertex_xyzw
  pipe_agent #(.DATA_W(27))  vnout_agent;   // TB sink:      consumes shade_vn_o

  clk_rst_ctrl              clk;
  vertex_processor_scoreboard scb;

  // Backpressure smoke hooks: when set, the corresponding output sink uses
  // the responder's stall-queue path (push_rdy_stall) instead of
  // always-ready. The test must set these in build_phase (the driver
  // samples std_sink once, at the start of its run_phase).
  bit stall_vout_sink  = 0;
  bit stall_vnout_sink = 0;

  `uvm_component_utils(env_vertex_processor)

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    clk = clk_rst_ctrl::type_id::create("clk", this);

    dma_req_agent = pipe_agent#(.DATA_W(32))::type_id::create("dma_req_agent", this);
    dma_req_agent.is_responder = 1;

    dma_rsp_agent = vp_dma_rsp_agent::type_id::create("dma_rsp_agent", this);

    vout_agent = pipe_agent#(.DATA_W(108))::type_id::create("vout_agent", this);
    vout_agent.is_responder = 1;

    vnout_agent = pipe_agent#(.DATA_W(27))::type_id::create("vnout_agent", this);
    vnout_agent.is_responder = 1;

    scb = vertex_processor_scoreboard::type_id::create("scb", this);
  endfunction

  function void connect_phase(uvm_phase phase);
    super.connect_phase(phase);
    // std_sink is set here (not in build_phase) because the pipe agents
    // assign drv.is_responder in their own build_phase, which runs after
    // this component's build_phase.
    dma_req_agent.drv.std_sink = 1; // accept DUT requests every cycle
    vout_agent.drv.std_sink    = stall_vout_sink  ? 0 : 1;
    vnout_agent.drv.std_sink   = stall_vnout_sink ? 0 : 1;
    // The vout/vnout outputs are FIFO WRITE ports, not AXI-style streams:
    // valid is a write-enable that DROPS while the FIFO reads full (w_norm's
    // output-freeze branch deasserts valid_o — the pending result stays in
    // the div pipeline and is re-presented when room returns; vn_shade's
    // output is modeled the same way). The legacy stream-style stall path
    // (wait for a valid, THEN hold ready low) deadlocks against this — the
    // 6th CAD-VM attempt (run xrun_tc_vertex_processor_basic_2026-09-24_
    // 21-19-38_24d5f1) showed exactly that: after the first free write
    // (start_ready=1), ready dropped to 0, w_norm froze (ro=0, valid_o=0),
    // the sink waited for a valid that only comes back with ready=1, and the
    // frame died at DMA word 34. fifo_sink models FIFO ROOM instead: ready=1
    // before the first write (an empty FIFO — a full-before-first-accept FIFO
    // is not physically reachable) and after each drain window; each queued
    // stall length becomes a post-accept "FIFO full" window. (No effect in
    // std-sink mode: the std path is taken first and ignores fifo_sink.)
    vout_agent.drv.fifo_sink   = stall_vout_sink  ? 1 : 0;
    vnout_agent.drv.fifo_sink  = stall_vnout_sink ? 1 : 0;

    dma_req_agent.mon.ap.connect(dma_rsp_agent.drv.req_imp); // DUT requests -> rsp driver
    dma_rsp_agent.mon.ap.connect(scb.in_export);             // accepted words -> scb parser
    vout_agent.mon.ap.connect(scb.pos_export);
    vnout_agent.mon.ap.connect(scb.shade_export);
  endfunction

endclass

`endif
