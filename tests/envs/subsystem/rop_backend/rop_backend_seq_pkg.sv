`ifndef ROP_BACKEND_SEQ_PKG_SV
`define ROP_BACKEND_SEQ_PKG_SV

package rop_backend_seq_pkg;
  import uvm_pkg::*;
  import pipe_pkg::*;
  import axi4lite_pkg::*;
  import rop_backend_env_pkg::*;
  `include "uvm_macros.svh"

  // Input pixel packing layout on the 96-bit data bus (in_if.data):
  //   [31:0]   x_i  — fixed point, 14 fractional bits (pixel = round(x_i/2^14))
  //   [63:32]  c_i  — signed 32-bit shaded intensity
  //   [95:64]  y_i  — fixed point, 14 fractional bits (pixel = round(y_i/2^14))

  class rop_backend_item extends pipe_item;
    logic [31:0]        x_i;
    logic [31:0]        y_i;
    logic signed [31:0] c_i;

    `uvm_object_utils_begin(rop_backend_item)
      `uvm_field_int(x_i, UVM_ALL_ON)
      `uvm_field_int(y_i, UVM_ALL_ON)
      `uvm_field_int(c_i, UVM_ALL_ON)
    `uvm_object_utils_end

    function new(string name = "rop_backend_item");
      super.new(name);
    endfunction

    function void pack_px();
      data  = {y_i, c_i, x_i};
      addr  = 32'h0;
      delay = 0;
    endfunction
  endclass

  // --- Single-pixel sequence ----------------------------------------------------
  class rop_backend_px_seq extends uvm_sequence #(pipe_item);
    `uvm_object_utils(rop_backend_px_seq)

    logic [31:0]        x_i;
    logic [31:0]        y_i;
    logic signed [31:0] c_i;

    function new(string name = "rop_backend_px_seq");
      super.new(name);
    endfunction

    task body();
      rop_backend_item item = rop_backend_item::type_id::create("item");
      start_item(item);
      item.x_i = x_i;
      item.y_i = y_i;
      item.c_i = c_i;
      item.pack_px();
      finish_item(item);
    endtask
  endclass

  // --- Random pixel-stream sequence ----------------------------------------------
  // Drives `n` pixels over the in-range 320x240 input domain (fixed point,
  // 14 fractional bits) with a configurable per-pixel idle gap. Exact-pixel
  // corner cases (boundaries, even/odd columns, specific intensities) are best
  // covered by dedicated `rop_backend_px_seq` instances in the test.
  class rop_backend_stream_seq extends uvm_sequence #(pipe_item);
    `uvm_object_utils(rop_backend_stream_seq)

    int unsigned     n        = 32;      // pixel count
    int unsigned     x_max_px = 319;     // max target pixel X
    int unsigned     y_max_px = 239;     // max target pixel Y
    int unsigned     gap_max  = 4;       // max idle cycles between pixels (0 = none)

    function new(string name = "rop_backend_stream_seq");
      super.new(name);
    endfunction

    task body();
      repeat (n) begin
        rop_backend_item item = rop_backend_item::type_id::create("item");
        // Pixel p lies in the input domain p*2^14 .. p*2^14 + 2^13-1 (rounding);
        // c_i spans the full signed range (negative -> color 0 at the DUT).
        start_item(item);
        item.x_i = $urandom % (x_max_px * 16384 + 1);
        item.y_i = $urandom % (y_max_px * 16384 + 1);
        item.c_i = $urandom;
        if (gap_max > 0)
          item.delay = $urandom_range(1, gap_max);
        item.pack_px();
        finish_item(item);
      end
    endtask
  endclass

  `include "rop_backend_base_test.sv"

endpackage

`endif
