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
        vif.ready <= 1'b1; // Default ready for responder
        forever @(posedge vif.clk);
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
