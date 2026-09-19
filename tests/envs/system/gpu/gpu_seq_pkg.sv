package gpu_seq_pkg;
  import uvm_pkg::*;
  import axi4lite_pkg::*;
  import clk_rst_pkg::*;
  import gpu_env_pkg::*;
  `include "uvm_macros.svh"

  class gpu_base_seq extends uvm_sequence;
    `uvm_object_utils(gpu_base_seq)
    function new(string name = "gpu_base_seq"); super.new(name); endfunction
  endclass

  // Host-bus AXI4-Lite write. `addr`/`data`/`strb`/`prot` are driven on the DUT's
  // exported s00 CPU port (full host-bus address). `resp` captures the DUT bresp.
  class gpu_axil_write_seq extends gpu_base_seq;
    logic [31:0] addr;
    logic [31:0] data;
    logic [3:0]  strb = 4'hF;
    logic [2:0]  prot = 3'h0;
    logic [1:0]  resp;
    `uvm_object_utils(gpu_axil_write_seq)
    function new(string name = "gpu_axil_write_seq"); super.new(name); endfunction
    task body();
      axi4lite_seq_item item = axi4lite_seq_item::type_id::create("item");
      start_item(item);
      item.op = WRITE;
      item.addr = addr;
      item.data = data;
      item.strb = strb;
      item.prot = prot;
      finish_item(item);
      resp = item.resp;
    endtask
  endclass

  // Host-bus AXI4-Lite read. `data`/`resp` capture the DUT's rdata/rresp after the
  // read completes (drive_read sets item.data=vif.rdata, axi4lite_pkg.sv:177-178)
  // so a test can assert on the returned word directly; the scoreboard remains the
  // authoritative check.
  class gpu_axil_read_seq extends gpu_base_seq;
    logic [31:0] addr;
    logic [2:0]  prot = 3'h0;
    logic [31:0] data;
    logic [1:0]  resp;
    `uvm_object_utils(gpu_axil_read_seq)
    function new(string name = "gpu_axil_read_seq"); super.new(name); endfunction
    task body();
      axi4lite_seq_item item = axi4lite_seq_item::type_id::create("item");
      start_item(item);
      item.op = READ;
      item.addr = addr;
      item.prot = prot;
      finish_item(item);
      data = item.data;
      resp = item.resp;
    endtask
  endclass

  `include "gpu_base_test.sv"
endpackage
