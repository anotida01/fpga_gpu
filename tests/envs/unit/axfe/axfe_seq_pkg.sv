package axfe_seq_pkg;
  import uvm_pkg::*;
  import axi4lite_pkg::*;
  import pipe_pkg::*;
  import gpu_hs_pkg::*;
  import axfe_env_pkg::*;
  `include "uvm_macros.svh"

  class axfe_base_seq extends uvm_sequence;
    `uvm_object_utils(axfe_base_seq)
    function new(string name = "axfe_base_seq"); super.new(name); endfunction
  endclass

  class axfe_axil_write_seq extends axfe_base_seq;
    logic [31:0] addr;
    logic [31:0] data;
    logic [3:0]  strb = 4'hF;   // WSTRB byte-select (default = full word)
    logic [2:0]  prot = 3'h0;   // axi4-lite prot field (default = 0)
    aw_w_mode_e  aw_w_mode = AW_W_SIMULTANEOUS;
    int unsigned aw_w_gap  = 0;
    // Captured DUT response (bresp) after the write completes. The driver sets
    // item.resp = vif.bresp before item_done() (axi4lite_pkg.sv drive_write_resp),
    // so reading it back here exposes the response to the test. Additive: no
    // existing test references resp, so behavior is unchanged for them.
    logic [1:0] resp;
    `uvm_object_utils(axfe_axil_write_seq)
    task body();
      axi4lite_seq_item item = axi4lite_seq_item::type_id::create("item");
      start_item(item);
      item.op = WRITE;
      item.addr = addr;
      item.data = data;
      item.strb = strb;
      item.prot = prot;
      item.aw_w_mode = aw_w_mode;
      item.aw_w_gap  = aw_w_gap;
      finish_item(item);
      resp = item.resp;
    endtask
  endclass

  class axfe_axil_read_seq extends axfe_base_seq;
    logic [31:0] addr;
    logic [2:0]  prot = 3'h0;   // axi4-lite prot field (default = 0)
    `uvm_object_utils(axfe_axil_read_seq)
    task body();
      axi4lite_seq_item item = axi4lite_seq_item::type_id::create("item");
      start_item(item);
      item.op = READ;
      item.addr = addr;
      item.prot = prot;
      finish_item(item);
    endtask
  endclass

  class axfe_dma_req_seq extends axfe_base_seq;
    logic [31:0] addr;
    `uvm_object_utils(axfe_dma_req_seq)
    task body();
      pipe_item item = pipe_item::type_id::create("item");
      start_item(item);
      item.addr = addr;
      item.delay = 1;
      finish_item(item);
    endtask
  endclass

  `include "axfe_base_test.sv"
endpackage
