`ifndef VN_SHADE_SEQ_PKG_SV
`define VN_SHADE_SEQ_PKG_SV

package vn_shade_seq_pkg;
  import uvm_pkg::*;
  import pipe_pkg::*;
  import vn_shade_env_pkg::*;
  `include "uvm_macros.svh"

  // Light preamble: three 27-bit signed Q13.14 words (Lx, Ly, Lz) plus
  // 1 hardware padding word to absorb the light-to-normal transition accept,
  // each with a 1-cycle inter-word delay.
  class vn_shade_light_seq extends uvm_sequence #(pipe_item);
    rand logic signed [26:0] lx;
    rand logic signed [26:0] ly;
    rand logic signed [26:0] lz;

    `uvm_object_utils(vn_shade_light_seq)

    function new(string name = "vn_shade_light_seq"); super.new(name); endfunction

    task body();
      pipe_item item;

      item = pipe_item::type_id::create("item_lx");
      start_item(item);
      item.data = 27'(lx);
      item.addr = 32'h0;
      item.delay = 1;
      finish_item(item);

      item = pipe_item::type_id::create("item_ly");
      start_item(item);
      item.data = 27'(ly);
      item.addr = 32'h0;
      item.delay = 1;
      finish_item(item);

      item = pipe_item::type_id::create("item_lz");
      start_item(item);
      item.data = 27'(lz);
      item.addr = 32'h0;
      item.delay = 1;
      finish_item(item);

      // Hardware padding word (absorbed by the light-phase transition accept)
      item = pipe_item::type_id::create("item_pad");
      start_item(item);
      item.data = 27'sd0;
      item.addr = 32'h0;
      item.delay = 1;
      finish_item(item);
    endtask
  endclass

  // Vertex normal: three 27-bit signed Q13.14 words (nx, ny, nz), one
  // accepted cycle each, with a 1-cycle inter-word delay.
  class vn_shade_normal_seq extends uvm_sequence #(pipe_item);
    rand logic signed [26:0] nx;
    rand logic signed [26:0] ny;
    rand logic signed [26:0] nz;

    `uvm_object_utils(vn_shade_normal_seq)

    function new(string name = "vn_shade_normal_seq"); super.new(name); endfunction

    task body();
      pipe_item item;

      item = pipe_item::type_id::create("item_nx");
      start_item(item);
      item.data = 27'(nx);
      item.addr = 32'h0;
      item.delay = 1;
      finish_item(item);

      item = pipe_item::type_id::create("item_ny");
      start_item(item);
      item.data = 27'(ny);
      item.addr = 32'h0;
      item.delay = 1;
      finish_item(item);

      item = pipe_item::type_id::create("item_nz");
      start_item(item);
      item.data = 27'(nz);
      item.addr = 32'h0;
      item.delay = 1;
      finish_item(item);
    endtask
  endclass

  `include "vn_shade_base_test.sv"

endpackage

`endif
