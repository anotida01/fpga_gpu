`ifndef ROP_SEQ_PKG_SV
`define ROP_SEQ_PKG_SV

package rop_seq_pkg;
  import uvm_pkg::*;
  import pipe_pkg::*;
  import rop_env_pkg::*;
  `include "uvm_macros.svh"

  // ROP transaction packing layout on 256-bit data bus:
  // Input side (241 bits used, 15 reserved):
  //   [31:0]   x_i
  //   [63:32]  y_i
  //   [95:64]  w0_i
  //   [127:96] w1_i
  //   [159:128]w2_i
  //   [186:160]c0_i (27 bits)
  //   [213:187]c1_i (27 bits)
  //   [240:214]c2_i (27 bits)
  //   [255:241]reserved (15 bits)
  // Output side (96 bits used, 160 reserved):
  //   [31:0]   x_o
  //   [63:32]  y_o
  //   [95:64]  c_o
  //   [255:96] reserved (160 bits)

  class rop_item extends pipe_item;
    logic signed [26:0] c0_i, c1_i, c2_i;
    logic signed [31:0] w0_i, w1_i, w2_i;
    logic [31:0]        x_i, y_i;

    `uvm_object_utils_begin(rop_item)
      `uvm_field_int(c0_i, UVM_ALL_ON)
      `uvm_field_int(c1_i, UVM_ALL_ON)
      `uvm_field_int(c2_i, UVM_ALL_ON)
      `uvm_field_int(w0_i, UVM_ALL_ON)
      `uvm_field_int(w1_i, UVM_ALL_ON)
      `uvm_field_int(w2_i, UVM_ALL_ON)
      `uvm_field_int(x_i, UVM_ALL_ON)
      `uvm_field_int(y_i, UVM_ALL_ON)
    `uvm_object_utils_end

    function void pack_input();
      data = { 15'h0,
               c2_i[26:0],
               c1_i[26:0],
               c0_i[26:0],
               w2_i,
               w1_i,
               w0_i,
               y_i,
               x_i };
      addr = 32'h0;
      delay = 0;
    endfunction

    function new(string name = "rop_item");
      super.new(name);
    endfunction
  endclass

  class rop_base_seq extends uvm_sequence #(rop_item);
    `uvm_object_utils(rop_base_seq)
    function new(string name = "rop_base_seq"); super.new(name); endfunction
  endclass

  class rop_in_seq extends rop_base_seq;
    logic signed [26:0] c0 = 27'sd1000;
    logic signed [26:0] c1 = 27'sd2000;
    logic signed [26:0] c2 = 27'sd3000;
    logic signed [31:0] w0 = 32'sd4096;   // e.g. Q13.14 scale
    logic signed [31:0] w1 = 32'sd4096;
    logic signed [31:0] w2 = 32'sd8192;
    logic [31:0]        x  = 32'd10;
    logic [31:0]        y  = 32'd20;

    `uvm_object_utils(rop_in_seq)

    function new(string name = "rop_in_seq"); super.new(name); endfunction

    task body();
      rop_item item = rop_item::type_id::create("item");
      start_item(item);
      item.c0_i = c0;
      item.c1_i = c1;
      item.c2_i = c2;
      item.w0_i = w0;
      item.w1_i = w1;
      item.w2_i = w2;
      item.x_i  = x;
      item.y_i  = y;
      item.pack_input();
      finish_item(item);
    endtask
  endclass

  `include "rop_base_test.sv"

endpackage

`endif
