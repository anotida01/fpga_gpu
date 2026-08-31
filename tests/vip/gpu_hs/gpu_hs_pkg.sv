package gpu_hs_pkg;
  import uvm_pkg::*;
  `include "uvm_macros.svh"

  class gpu_hs_item extends uvm_sequence_item;
    rand int done_delay;
    `uvm_object_utils_begin(gpu_hs_item)
      `uvm_field_int(done_delay, UVM_ALL_ON)
    `uvm_object_utils_end

    function new(string name = "gpu_hs_item");
      super.new(name);
      done_delay = 1;
    endfunction
  endclass

  typedef uvm_sequencer #(gpu_hs_item) gpu_hs_sequencer;

  class gpu_hs_driver extends uvm_driver #(gpu_hs_item);
    virtual gpu_hs_if vif;
    `uvm_component_utils(gpu_hs_driver)

    function new(string name, uvm_component parent);
      super.new(name, parent);
    endfunction

    task run_phase(uvm_phase phase);
      vif.done <= 1'b0;
      forever begin
        // Wait for start from DUT
        @(posedge vif.clk);
        if (vif.start) begin
          int delay = 1;
          repeat(delay) @(posedge vif.clk);
          vif.done <= 1'b1;
          @(posedge vif.clk);
          vif.done <= 1'b0;
        end
      end
    endtask
  endclass

  class gpu_hs_monitor extends uvm_monitor;
    virtual gpu_hs_if vif;
    uvm_analysis_port #(gpu_hs_item) ap;
    `uvm_component_utils(gpu_hs_monitor)

    function new(string name, uvm_component parent);
      super.new(name, parent);
      ap = new("ap", this);
    endfunction

    task run_phase(uvm_phase phase);
      forever begin
        @(vif.mon_cb);
        if (vif.mon_cb.start) begin
          gpu_hs_item item = gpu_hs_item::type_id::create("item");
          ap.write(item);
        end
      end
    endtask
  endclass

  class gpu_hs_agent extends uvm_agent;
    gpu_hs_sequencer sqr;
    gpu_hs_driver drv;
    gpu_hs_monitor mon;
    virtual gpu_hs_if vif;

    `uvm_component_utils(gpu_hs_agent)

    function new(string name, uvm_component parent);
      super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
      mon = gpu_hs_monitor::type_id::create("mon", this);
      sqr = gpu_hs_sequencer::type_id::create("sqr", this);
      drv = gpu_hs_driver::type_id::create("drv", this);
      if (!uvm_config_db#(virtual gpu_hs_if)::get(this, "", "vif", vif))
        `uvm_fatal("VIF", "No vif for gpu_hs_agent")
      mon.vif = vif;
      drv.vif = vif;
    endfunction

    function void connect_phase(uvm_phase phase);
      drv.seq_item_port.connect(sqr.seq_item_export);
      drv.vif = vif;
    endfunction
  endclass

endpackage
