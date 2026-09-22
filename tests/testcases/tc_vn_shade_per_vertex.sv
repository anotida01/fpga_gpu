`ifndef TC_VN_SHADE_PER_VERTEX_SV
`define TC_VN_SHADE_PER_VERTEX_SV
`timescale 1ps/1ps
import uvm_pkg::*;
import pipe_pkg::*;
import vn_shade_env_pkg::*;
import vn_shade_seq_pkg::*;
`include "uvm_macros.svh"

// Directed per-vertex dot-product test: drives a known light and directed
// streams of DISTINCT vertex normals, and lets the env scoreboard assert
// each per-vertex vn_o against the intended Q13.14 N.L (the scoreboard
// computes the golden inline: exact 64-bit sum, arithmetic shift >>> 14,
// no tolerance).
//
// Because every driven normal is distinct from its neighbors, both a
// light-component desync (a normal component paired with the wrong light
// component) and a stream shift (spurious leading 0, so output n is
// scored against vertex n+1) surface as ordered scoreboard mismatches.
// The scoreboard compares outputs strictly in order against the expected
// queue and has no skip/absorb logic, so the FIRST output must equal the
// FIRST vertex's N.L — a spurious leading 0 is a mismatch, never absorbed.
//
// Frame 2 drives the 36-vertex box normal stream (the normal fields of the
// 7-word vertex records in tests/testcases/memh/box.memh) with the box
// light — the exact per-vertex regression the system golden test hits;
// the intended per-vertex values equal
// tests/testcases/memh/shade.memh under that light.

class tc_vn_shade_per_vertex extends vn_shade_base_test;
  `uvm_component_utils(tc_vn_shade_per_vertex)

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  // 36 box normals (Q13.14, 1.0 = 16384) in vertex order: the (xn, yn, zn)
  // fields of the 7-word vertex records in tests/testcases/memh/box.memh.
  // Twelve flat triangles (3 vertices each, identical normal per triangle);
  // under the box light (10711, -10081, 7217) each triangle's N.L matches
  // the corresponding 3-line block of tests/testcases/memh/shade.memh.
  localparam logic signed [26:0] BOX_NRM [107:0] = '{
    // tri  0: v0-v2   N=(-1, 0, 0) -> N.L = -10711
    -16384, 0, 0,   -16384, 0, 0,   -16384, 0, 0,
    // tri  1: v3-v5   N=( 0, 0,-1) -> N.L =  -7217
     0,    0, -16384,    0,    0, -16384,    0,    0, -16384,
    // tri  2: v6-v8   N=( 0, 1, 0) -> N.L = -10081
     0, 16384,    0,    0, 16384,    0,    0, 16384,    0,
    // tri  3: v9-v11  N=( 0, 0, 1) -> N.L =  +7217
     0,    0, 16384,    0,    0, 16384,    0,    0, 16384,
    // tri  4: v12-v14 N=( 0,-1, 0) -> N.L = +10081
     0, -16384,    0,    0, -16384,    0,    0, -16384,    0,
    // tri  5: v15-v17 N=( 1, 0, 0) -> N.L = +10711
 16384,    0,    0, 16384,    0,    0, 16384,    0,    0,
    // tri  6: v18-v20 N=(-1, 0, 0) -> N.L = -10711
    -16384, 0, 0,   -16384, 0, 0,   -16384, 0, 0,
    // tri  7: v21-v23 N=( 0, 0,-1) -> N.L =  -7217
     0,    0, -16384,    0,    0, -16384,    0,    0, -16384,
    // tri  8: v24-v26 N=( 0, 1, 0) -> N.L = -10081
     0, 16384,    0,    0, 16384,    0,    0, 16384,    0,
    // tri  9: v27-v29 N=( 0, 0, 1) -> N.L =  +7217
     0,    0, 16384,    0,    0, 16384,    0,    0, 16384,
    // tri 10: v30-v32 N=( 0,-1, 0) -> N.L = +10081
     0, -16384,    0,    0, -16384,    0,    0, -16384,    0,
    // tri 11: v33-v35 N=( 1, 0, 0) -> N.L = +10711
 16384,    0,    0, 16384,    0,    0, 16384,    0,    0
  };

  task run_phase(uvm_phase phase);
    phase.raise_objection(this);

    // -------------------------------------------------------------------
    // Frame 1: box light + 8 directed normals (distinct, in order)
    // -------------------------------------------------------------------
    wait_for_reset();

    `uvm_info("TC", "Frame 1: box light (10711, -10081, 7217) + 8 directed normals", UVM_LOW)

    // Light preamble (Q13.14, 1.0 = 16384): all three components non-zero
    // so a light-component desync is observable.
    send_light(27'sd10711, -27'sd10081, 27'sd7217);

    // Directed normals (Q13.14), each distinct from its neighbors so a
    // stream shift AND a component desync both show up as mismatches.
    // Intended per-vertex N.L (computed inline by the scoreboard, never
    // hardcoded):
    //   v1 (-1, 0, 0)      -> -10711   (the FIRST output must be this, not 0)
    //   v2 ( 0, 0, -1)     ->  -7217
    //   v3 ( 0, 1,  0)     -> -10081
    //   v4 ( 0, 0,  1)     ->  +7217
    //   v5 ( 0,-1,  0)     -> +10081
    //   v6 ( 1, 0,  0)     -> +10711
    //   v7 (0.5, 0.5, 0.5) ->  +3923   (multi-component — exposes desync)
    //   v8 (-0.5, 0, 0.5)  ->  -1747   (multi-component, mixed sign)
    send_normal(-27'sd16384, 27'sd0,       27'sd0);
    send_normal( 27'sd0,     27'sd0,     -27'sd16384);
    send_normal( 27'sd0,      27'sd16384, 27'sd0);
    send_normal( 27'sd0,     27'sd0,       27'sd16384);
    send_normal( 27'sd0,    -27'sd16384,   27'sd0);
    send_normal( 27'sd16384, 27'sd0,       27'sd0);
    send_normal( 27'sd8192,   27'sd8192,   27'sd8192);
    send_normal(-27'sd8192,   27'sd0,       27'sd8192);

    // Drain the DUT's output pipeline before the frame-boundary reset.
    wait_drained();

    // -------------------------------------------------------------------
    // Frame 2: box light + 36-vertex box normal stream (the per-vertex
    // regression the system golden test hits)
    // -------------------------------------------------------------------
    new_frame();

    `uvm_info("TC", "Frame 2: box light (10711, -10081, 7217) + 36-vertex box normal stream", UVM_LOW)

    send_light(27'sd10711, -27'sd10081, 27'sd7217);

    for (int i = 0; i < 36; i++)
      send_normal(BOX_NRM[3*i], BOX_NRM[3*i+1], BOX_NRM[3*i+2]);

    wait_drained();

    #500ns;
    `uvm_info("TC", "Finished tc_vn_shade_per_vertex transactions.", UVM_LOW)
    phase.drop_objection(this);
  endtask

endclass

`endif
