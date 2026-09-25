`ifndef TC_VERTEX_PROCESSOR_BASIC_SV
`define TC_VERTEX_PROCESSOR_BASIC_SV
`timescale 1ps/1ps

import uvm_pkg::*;
import pipe_pkg::*;
import clk_rst_pkg::*;
import vertex_processor_env_pkg::*;
import vertex_processor_seq_pkg::*;

`include "uvm_macros.svh"

// Directed, cmodel-free subsystem smoke test with inline scoring: the
// scoreboard's own exact Q13.14 model (xform row sums + LPM w_norm +
// 3-term shade dot) is the expected-value authority.
//
// Three frames, all under the identity matrix (Q13.14, 1.0 = 16384), so
// the pos channel must return the input coordinates unchanged with
// w = 16384:
//
//   Frame 1: box light (10711, -10081, 7217) + 3 axis vertices with axis
//            normals - expected shade = the light's axis component
//            (10711, -10081, 7217 in vertex order).
//   Frame 2: light (1, 0, 0) + the same 3 vertices - exercises the
//            per-frame light re-latch; expected shade (16384, 0, 0).
//   Frame 3: same as frame 1, with backpressure stalls on the vertex and
//            normal output sinks (true ready-low backpressure, then
//            release; the DUT pipeline must stall and resume in order).
//
// The scoreboard compares outputs strictly in vertex order with no
// skip/absorb logic, so the first output of each frame must equal the
// first vertex's expected value - a spurious leading word is a
// mismatch, never absorbed.

class tc_vertex_processor_basic extends vertex_processor_base_test;
  `uvm_component_utils(tc_vertex_processor_basic)

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    // Route both output sinks through the responder's FIFO write-port path
    // (fifo_sink + stall queue — see env connect_phase) so frame 3 can
    // apply real backpressure (must be set before the drivers sample the
    // sink mode at the start of their run_phase).
    env.stall_vout_sink  = 1;
    env.stall_vnout_sink = 1;
  endfunction

  // Push this frame's output stalls, in output order (one entry per
  // expected output, 3 per frame). The sinks are FIFO write-port sinks
  // (pipe_driver fifo_sink mode — see env connect_phase): entry k is a
  // post-accept "FIFO full" window applied AFTER the (k+1)-th output is
  // written, so the middle entry stalls the pipeline between the middle and
  // the last output of the frame (the DUT must hold the pending result in
  // its pipeline and re-present it when the FIFO has room again).
  protected task push_stalls(int unsigned vout_stall, int unsigned vnout_stall);
    env.vout_agent.drv.push_rdy_stall(0);
    env.vout_agent.drv.push_rdy_stall(vout_stall);
    env.vout_agent.drv.push_rdy_stall(0);
    env.vnout_agent.drv.push_rdy_stall(0);
    env.vnout_agent.drv.push_rdy_stall(vnout_stall);
    env.vnout_agent.drv.push_rdy_stall(0);
  endtask

  task run_phase(uvm_phase phase);
    int mat[16];
    int light[3];
    int vtx_words[$];

    phase.raise_objection(this);

    // Identity matrix (Q13.14): diagonal 16384, w row (0,0,0,16384).
    foreach (mat[i]) mat[i] = 0;
    mat[0]  = 16384;
    mat[5]  = 16384;
    mat[10] = 16384;
    mat[15] = 16384;

    // 3 axis vertices: pos (unit axis, w = 1.0) + matching axis normal.
    // Word order per vertex group: 4 position words, then 3 normal words.
    vtx_words = '{ 16384, 0,     0,     16384,  16384, 0,     0,
                    0,     16384, 0,     16384,  0,     16384, 0,
                    0,     0,     16384, 16384,  0,     0,     16384 };

    wait_for_reset();

    // -------------------------------------------------------------------
    // Frame 1: box light + axis vertices
    // -------------------------------------------------------------------
    light = '{ 10711, -10081, 7217 };
    `uvm_info("TC", "Frame 1: identity matrix, box light, 3 axis vertices", UVM_LOW)
    env.scb.reset_state();
    push_stalls(0, 0);
    send_frame(mat, light, vtx_words);

    // -------------------------------------------------------------------
    // Frame 2: light (1,0,0) - per-frame light re-latch
    // -------------------------------------------------------------------
    light = '{ 16384, 0, 0 };
    `uvm_info("TC", "Frame 2: identity matrix, light (1,0,0), 3 axis vertices", UVM_LOW)
    env.scb.reset_state();
    push_stalls(0, 0);
    send_frame(mat, light, vtx_words);

    // -------------------------------------------------------------------
    // Frame 3: box light + axis vertices, output backpressure stalls
    // -------------------------------------------------------------------
    light = '{ 10711, -10081, 7217 };
    `uvm_info("TC", "Frame 3: identity matrix, box light, 3 axis vertices, output stalls", UVM_LOW)
    env.scb.reset_state();
    push_stalls(8, 5);
    send_frame(mat, light, vtx_words);

    #500ns;
    `uvm_info("TC", "Finished tc_vertex_processor_basic transactions.", UVM_LOW)
    phase.drop_objection(this);
  endtask

endclass

`endif
