package pipe_pkg;
  import uvm_pkg::*;
  `include "uvm_macros.svh"

  class pipe_item extends uvm_sequence_item;
    rand logic [31:0]   addr;
    rand logic [255:0]  data;
    rand int            delay;

    `uvm_object_utils_begin(pipe_item)
      `uvm_field_int(addr, UVM_ALL_ON)
      `uvm_field_int(data, UVM_ALL_ON)
      `uvm_field_int(delay, UVM_ALL_ON)
    `uvm_object_utils_end

    function new(string name = "pipe_item");
      super.new(name);
    endfunction
  endclass

  typedef uvm_sequencer #(pipe_item) pipe_sequencer;

  class pipe_driver #(parameter int DATA_W = 32) extends uvm_driver #(pipe_item);
    virtual pipe_if#(.DATA_W(DATA_W)) vif;
    bit is_responder = 0; // 0: drives valid/data/addr, 1: drives ready
    bit std_sink     = 0; // 0: wait-then-ready response, 1: always-ready (std sink)
    // Initial ready level for the non-std (stall-queue) responder path.
    // Default 0 = legacy: ready low until the first valid is seen.
    // Set 1 when the modeled downstream FIFO is EMPTY (not full) before the
    // first output is accepted — a FIFO that reads full before it has accepted
    // anything is not physically reachable, and it deadlocks DUTs whose first
    // output is gated on ~full (the sink would wait for a valid that the
    // blocked DUT never emits). Note: with start_ready=1 the first item is
    // accepted immediately (no queue entry consumed), so push stall 0 as the
    // first queue entry to keep per-item mapping.
    bit start_ready  = 0;
    // FIFO write-enable sink (third responder mode). Use when the DUT's
    // output is a FIFO WRITE PORT rather than an AXI-style stream: valid is a
    // write-enable that DROPS while the FIFO reads full (the DUT holds the
    // pending result in its pipeline and re-presents it when room returns —
    // it does NOT hold valid through backpressure). The legacy stream-style
    // path above (wait for a valid, then hold ready low) deadlocks against
    // such DUTs: ready stays low waiting for a valid the DUT only
    // (re)presents when ready is high. fifo_sink instead models a real FIFO:
    // the write is LATCHED ON THE CLOCK POSEDGE (one write per posedge at
    // which valid & ready are both 1 in the active region — the pre-edge
    // values, exactly what a downstream FIFO clocking on the same edge would
    // capture), and ready is driven from occupancy: 1 before the first write
    // (an empty FIFO), 0 after each accepted write, 1 again after the queued
    // drain window. Each queued stall length is that post-accept "FIFO full"
    // window (ready held low for that many cycles; 0 = the FIFO is drained
    // and ready stays 1).
    //
    // The edge latch is LOAD-BEARING, not stylistic: a level-sensitive
    // re-check after the edge spins in a zero-delay loop — the DUT's
    // valid_o deasserts via NBA on the edge AFTER the pulse, so a stale 1
    // satisfies an immediate re-check infinitely within the same delta (the
    // 7th CAD-VM attempt burned 200 s CPU and never left the first vout
    // write). Every loop iteration must cross at least one clock edge.
    //
    // X-tolerant by construction: the write condition requires valid===1 AND
    // ready===1, so a pre-reset X can neither latch a write nor consume a
    // queue entry.
    bit fifo_sink    = 0;
    // Responder-owned backpressure: a queue of stall lengths (cycles to hold
    // ready low) applied to successive valid/ready handshakes. A test pushes one
    // entry per expected response (in order); the responder pops the front
    // before releasing ready (0 if the queue is empty). A queue (not a scalar)
    // keeps values applied in order despite the test thread advancing ahead of
    // the async responder — the DUT's own ready gating already serializes
    // successive req/rsp, so pop order == req order.
    int unsigned rdy_stall_q[$];

    // Push a stall length for the next response this responder will service.
    function void push_rdy_stall(int unsigned cyc);
      rdy_stall_q.push_back(cyc);
    endfunction

    `uvm_component_param_utils(pipe_driver#(DATA_W))

    function new(string name, uvm_component parent);
      super.new(name, parent);
    endfunction

    task run_phase(uvm_phase phase);
      if (!is_responder) begin
        vif.valid <= 1'b0;
        vif.addr  <= 32'h0;
        vif.data  <= '0;
        forever begin
          seq_item_port.get_next_item(req);
          repeat(req.delay) @(posedge vif.clk);
          vif.addr  <= req.addr;
          vif.data  <= req.data;
          vif.valid <= 1'b1;
          do @(posedge vif.clk); while (!vif.ready);
          vif.valid <= 1'b0;
          seq_item_port.item_done();
        end
      end else begin
        if (std_sink) begin
          vif.ready <= 1'b1;
          forever @(posedge vif.clk);
        end else if (fifo_sink) begin
          int unsigned stall;
          vif.ready <= 1'b1; // modeled FIFO starts EMPTY (room to write)
          forever begin
            // Latch the write on the clock edge, like a real FIFO: at each
            // posedge, if valid & ready are both 1 (sampled in the active
            // region — the pre-edge values), exactly one word is sunk. Never
            // re-check within the same delta (see the zero-delay spin note in
            // the fifo_sink comment above).
            @(posedge vif.clk);
            if (vif.valid === 1'b1 && vif.ready === 1'b1) begin
              // Write accepted — the FIFO now reads full; the queued drain
              // window (if any) extends how long it stays full. The DUT's
              // write-enable drops for the window and the pending result is
              // re-presented when room returns.
              stall = (rdy_stall_q.size() > 0) ? rdy_stall_q.pop_front() : 0;
              vif.ready <= 1'b0;
              if (stall > 0)
                repeat (stall) @(posedge vif.clk);
              vif.ready <= 1'b1; // drained — room again
            end
          end
        end else begin
          int unsigned stall;
          vif.ready <= start_ready;
          forever begin
            // Wait for the source to offer a transaction (valid asserted).
            // X-tolerant: a pre-reset X on valid must NOT exit the wait (X is
            // "false" in a boolean context) — the 5th CAD-VM attempt showed the
            // X race at t=0 burning the first stall-queue entry and dropping
            // ready two cycles in, negating start_ready=1.
            while (!(vif.valid === 1'b1)) @(posedge vif.clk);
            // TRUE backpressure: while the source holds valid (word retention),
            // hold ready LOW for `stall` cycles (0 = none, preserving the legacy
            // always-ready behavior). A single responder process keeps this
            // applied in request order — the DUT's own ready gating serializes
            // successive req/rsp, so each stall maps to the correct response.
            stall = (rdy_stall_q.size() > 0) ? rdy_stall_q.pop_front() : 0;
            if (stall > 0)
              repeat (stall) @(posedge vif.clk);
            // Release ready for one cycle: the valid/ready handshake now completes.
            vif.ready <= 1'b1;
            @(posedge vif.clk);
            vif.ready <= 1'b0;
            // Ensure the source has deasserted valid (moved on) before servicing
            // the next transaction, so we do not double-catch the same valid.
            // X-tolerant (same rationale as above): wait until valid is a
            // definite 0, not "not-1".
            while (!(vif.valid === 1'b0)) @(posedge vif.clk);
          end
        end
      end
    endtask
  endclass

  class pipe_monitor #(parameter int DATA_W = 32) extends uvm_monitor;
    virtual pipe_if#(.DATA_W(DATA_W)) vif;
    uvm_analysis_port #(pipe_item) ap;
    `uvm_component_param_utils(pipe_monitor#(DATA_W))

    function new(string name, uvm_component parent);
      super.new(name, parent);
      ap = new("ap", this);
    endfunction

    task run_phase(uvm_phase phase);
      forever begin
        @(vif.mon_cb);
        if (vif.mon_cb.valid && vif.mon_cb.ready) begin
          pipe_item item = pipe_item::type_id::create("item");
          item.addr = vif.mon_cb.addr;
          item.data = vif.mon_cb.data;
          ap.write(item);
        end
      end
    endtask
  endclass

  class pipe_agent #(parameter int DATA_W = 32) extends uvm_agent;
    bit is_responder = 0;
    pipe_sequencer sqr;
    pipe_driver#(.DATA_W(DATA_W)) drv;
    pipe_monitor#(.DATA_W(DATA_W)) mon;
    virtual pipe_if#(.DATA_W(DATA_W)) vif;

    `uvm_component_param_utils(pipe_agent#(DATA_W))

    function new(string name, uvm_component parent);
      super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
      mon = pipe_monitor#(.DATA_W(DATA_W))::type_id::create("mon", this);
      sqr = pipe_sequencer::type_id::create("sqr", this);
      drv = pipe_driver#(.DATA_W(DATA_W))::type_id::create("drv", this);
      if (!uvm_config_db#(virtual pipe_if#(.DATA_W(DATA_W)))::get(this, "", "vif", vif))
        `uvm_fatal("VIF", "No vif for pipe_agent")
      mon.vif = vif;
      drv.vif = vif;
      drv.is_responder = is_responder;
    endfunction

    function void connect_phase(uvm_phase phase);
      drv.seq_item_port.connect(sqr.seq_item_export);
      drv.vif = vif;
    endfunction
  endclass

endpackage
