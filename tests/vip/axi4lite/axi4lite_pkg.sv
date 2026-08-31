package axi4lite_pkg;
  import uvm_pkg::*;
  `include "uvm_macros.svh"

  typedef enum { READ, WRITE } op_type_e;

  class axi4lite_seq_item extends uvm_sequence_item;
    rand op_type_e op;
    rand logic [31:0] addr;
    rand logic [31:0] data;
    rand logic [3:0]  strb;
    rand logic [2:0]  prot;
    
    logic [1:0] resp;
    
    `uvm_object_utils_begin(axi4lite_seq_item)
      `uvm_field_enum(op_type_e, op, UVM_ALL_ON)
      `uvm_field_int(addr, UVM_ALL_ON)
      `uvm_field_int(data, UVM_ALL_ON)
      `uvm_field_int(strb, UVM_ALL_ON)
      `uvm_field_int(prot, UVM_ALL_ON)
      `uvm_field_int(resp, UVM_ALL_ON)
    `uvm_object_utils_end

    function new(string name = "axi4lite_seq_item");
      super.new(name);
    endfunction
  endclass

  typedef uvm_sequencer #(axi4lite_seq_item) axi4lite_sequencer;

  // --- Memory Model ---
  class axi4lite_mem_model extends uvm_component;
    logic [31:0] mem[logic [31:0]];
    `uvm_component_utils(axi4lite_mem_model)
    function new(string name, uvm_component parent);
      super.new(name, parent);
    endfunction
    function void write(logic [31:0] addr, logic [31:0] data);
      mem[addr] = data;
    endfunction
    function logic [31:0] read(logic [31:0] addr);
      if (mem.exists(addr)) return mem[addr];
      return 32'hX;
    endfunction
  endclass

  // --- Master Driver ---
  class axi4lite_master_driver extends uvm_driver #(axi4lite_seq_item);
    virtual axi4lite_if vif;
    `uvm_component_utils(axi4lite_master_driver)

    function new(string name, uvm_component parent);
      super.new(name, parent);
    endfunction

    task run_phase(uvm_phase phase);
      vif.awaddr  <= '0;
      vif.awprot  <= '0;
      vif.awvalid <= 1'b0;
      vif.wdata   <= '0;
      vif.wstrb   <= '0;
      vif.wvalid  <= 1'b0;
      vif.bready  <= 1'b0;
      vif.araddr  <= '0;
      vif.arprot  <= '0;
      vif.arvalid <= 1'b0;
      vif.rready  <= 1'b0;
      
      forever begin
        seq_item_port.get_next_item(req);
        if (req.op == WRITE) drive_write(req);
        else                 drive_read(req);
        seq_item_port.item_done();
      end
    endtask

    task drive_write(axi4lite_seq_item item);
      @(posedge vif.clk);
      vif.awaddr  <= item.addr;
      vif.awprot  <= item.prot;
      vif.awvalid <= 1'b1;
      vif.wdata   <= item.data;
      vif.wstrb   <= item.strb;
      vif.wvalid  <= 1'b1;
      
      fork
        begin
          do @(posedge vif.clk); while (!vif.awready);
          vif.awvalid <= 1'b0;
        end
        begin
          do @(posedge vif.clk); while (!vif.wready);
          vif.wvalid <= 1'b0;
        end
      join
      
      vif.bready <= 1'b1;
      do @(posedge vif.clk); while (!vif.bvalid);
      item.resp = vif.bresp;
      vif.bready <= 1'b0;
    endtask

    task drive_read(axi4lite_seq_item item);
      @(posedge vif.clk);
      vif.araddr  <= item.addr;
      vif.arprot  <= item.prot;
      vif.arvalid <= 1'b1;
      do @(posedge vif.clk); while (!vif.arready);
      vif.arvalid <= 1'b0;
      
      vif.rready <= 1'b1;
      do @(posedge vif.clk); while (!vif.rvalid);
      item.data = vif.rdata;
      item.resp = vif.rresp;
      vif.rready <= 1'b0;
    endtask
  endclass

  // --- Slave Driver (Responder) ---
  class axi4lite_slave_driver extends uvm_driver #(axi4lite_seq_item);
    virtual axi4lite_if vif;
    axi4lite_mem_model mem_model;
    `uvm_component_utils(axi4lite_slave_driver)

    function new(string name, uvm_component parent);
      super.new(name, parent);
    endfunction

    task run_phase(uvm_phase phase);
      vif.awready <= 1'b0;
      vif.wready  <= 1'b0;
      vif.bvalid  <= 1'b0;
      vif.bresp   <= 2'b00;
      vif.arready <= 1'b0;
      vif.rvalid  <= 1'b0;
      vif.rdata   <= 32'h0;
      vif.rresp   <= 2'b00;
      
      fork
        forever handle_write();
        forever handle_read();
      join
    endtask

    task handle_write();
      logic [31:0] wr_addr;
      logic [31:0] wr_data;
      @(posedge vif.clk);
      vif.awready <= 1'b1;
      vif.wready  <= 1'b1;
      fork
        begin
          do @(posedge vif.clk); while (!vif.awvalid);
          wr_addr = vif.awaddr;
          vif.awready <= 1'b0;
        end
        begin
          do @(posedge vif.clk); while (!vif.wvalid);
          wr_data = vif.wdata;
          vif.wready <= 1'b0;
        end
      join
      if (mem_model != null) begin
        mem_model.write(wr_addr, wr_data);
      end
      vif.bresp   <= 2'b00; // OKAY
      vif.bvalid  <= 1'b1;
      do @(posedge vif.clk); while (!vif.bready);
      vif.bvalid  <= 1'b0;
    endtask

    task handle_read();
      logic [31:0] rd_addr;
      @(posedge vif.clk);
      vif.arready <= 1'b1;
      do @(posedge vif.clk); while (!vif.arvalid);
      rd_addr = vif.araddr;
      vif.arready <= 1'b0;
      
      if (mem_model != null) begin
        vif.rdata <= mem_model.read(rd_addr);
      end else begin
        vif.rdata <= 32'h0;
      end
      vif.rresp   <= 2'b00; // OKAY
      vif.rvalid  <= 1'b1;
      do @(posedge vif.clk); while (!vif.rready);
      vif.rvalid  <= 1'b0;
    endtask
  endclass

  // --- Monitor ---
  class axi4lite_monitor extends uvm_monitor;
    virtual axi4lite_if vif;
    uvm_analysis_port #(axi4lite_seq_item) ap;
    `uvm_component_utils(axi4lite_monitor)

    function new(string name, uvm_component parent);
      super.new(name, parent);
      ap = new("ap", this);
    endfunction

    task run_phase(uvm_phase phase);
      fork
        forever monitor_write();
        forever monitor_read();
      join
    endtask

    task monitor_write();
      axi4lite_seq_item item;
      logic [31:0] addr;
      logic [31:0] data;
      logic [3:0]  strb;
      fork
        begin
          do @(vif.mon_cb); while (!(vif.mon_cb.awvalid && vif.mon_cb.awready));
          addr = vif.mon_cb.awaddr;
        end
        begin
          do @(vif.mon_cb); while (!(vif.mon_cb.wvalid && vif.mon_cb.wready));
          data = vif.mon_cb.wdata;
          strb = vif.mon_cb.wstrb;
        end
      join
      do @(vif.mon_cb); while (!(vif.mon_cb.bvalid && vif.mon_cb.bready));
      item = axi4lite_seq_item::type_id::create("item");
      item.op = WRITE;
      item.addr = addr;
      item.data = data;
      item.strb = strb;
      item.resp = vif.mon_cb.bresp;
      ap.write(item);
    endtask

    task monitor_read();
      axi4lite_seq_item item;
      logic [31:0] addr;
      do @(vif.mon_cb); while (!(vif.mon_cb.arvalid && vif.mon_cb.arready));
      addr = vif.mon_cb.araddr;
      do @(vif.mon_cb); while (!(vif.mon_cb.rvalid && vif.mon_cb.rready));
      item = axi4lite_seq_item::type_id::create("item");
      item.op = READ;
      item.addr = addr;
      item.data = vif.mon_cb.rdata;
      item.resp = vif.mon_cb.rresp;
      ap.write(item);
    endtask
  endclass

  // --- Agent ---
  class axi4lite_agent extends uvm_agent;
    uvm_active_passive_enum is_active = UVM_ACTIVE;
    bit is_master = 1;
    axi4lite_sequencer sqr;
    axi4lite_master_driver m_drv;
    axi4lite_slave_driver  s_drv;
    axi4lite_monitor mon;
    virtual axi4lite_if vif;

    `uvm_component_utils(axi4lite_agent)

    function new(string name, uvm_component parent);
      super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
      mon = axi4lite_monitor::type_id::create("mon", this);
      if (is_active == UVM_ACTIVE) begin
        sqr = axi4lite_sequencer::type_id::create("sqr", this);
        if (is_master) m_drv = axi4lite_master_driver::type_id::create("m_drv", this);
        else           s_drv = axi4lite_slave_driver::type_id::create("s_drv", this);
      end
      if (!uvm_config_db#(virtual axi4lite_if)::get(this, "", "vif", vif))
        `uvm_fatal("VIF", "Could not get vif")
      mon.vif = vif;
    endfunction

    function void connect_phase(uvm_phase phase);
      if (is_active == UVM_ACTIVE) begin
        if (is_master) begin
          m_drv.seq_item_port.connect(sqr.seq_item_export);
          m_drv.vif = vif;
        end else begin
          s_drv.vif = vif;
        end
      end
    endfunction
  endclass

endpackage
