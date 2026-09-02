package pipe_pkg;
  import uvm_pkg::*;
  `include "uvm_macros.svh"

  class pipe_item extends uvm_sequence_item;
    rand logic [31:0] addr;
    rand logic [31:0] data;
    rand int          delay;

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

  class pipe_driver extends uvm_driver #(pipe_item);
    virtual pipe_if vif;
    bit is_responder = 0; // 0: drives valid/data/addr, 1: drives ready
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

    `uvm_component_utils(pipe_driver)

    function new(string name, uvm_component parent);
      super.new(name, parent);
    endfunction

    task run_phase(uvm_phase phase);
      if (!is_responder) begin
        vif.valid <= 1'b0;
        vif.addr  <= 32'h0;
        vif.data  <= 32'h0;
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
        int unsigned stall;
        vif.ready <= 1'b0;
        forever begin
          // Wait for the source to offer a transaction (valid asserted).
          while (!vif.valid) @(posedge vif.clk);
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
          while (vif.valid) @(posedge vif.clk);
        end
      end
    endtask
  endclass

  class pipe_monitor extends uvm_monitor;
    virtual pipe_if vif;
    uvm_analysis_port #(pipe_item) ap;
    `uvm_component_utils(pipe_monitor)

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

  class pipe_agent extends uvm_agent;
    bit is_responder = 0;
    pipe_sequencer sqr;
    pipe_driver drv;
    pipe_monitor mon;
    virtual pipe_if vif;

    `uvm_component_utils(pipe_agent)

    function new(string name, uvm_component parent);
      super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
      mon = pipe_monitor::type_id::create("mon", this);
      sqr = pipe_sequencer::type_id::create("sqr", this);
      drv = pipe_driver::type_id::create("drv", this);
      if (!uvm_config_db#(virtual pipe_if)::get(this, "", "vif", vif))
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
