`ifndef TC_ROP_BACKEND_BASIC_SV
`define TC_ROP_BACKEND_BASIC_SV
`timescale 1ps/1ps
import uvm_pkg::*;
import pipe_pkg::*;
import axi4lite_pkg::*;
import rop_backend_env_pkg::*;
import rop_backend_seq_pkg::*;
`include "uvm_macros.svh"

// Basic functionality test for the axil_rop_backend subsystem env:
//  - directed pixels using the canonical contract intensities (black 0x0000,
//    quarter 0x39C7, half 0x7BCF, three-quarter 0xBDE7, white 0xFFFF),
//    a zero-clamp on negative intensity, out-of-domain saturating-white
//    probes (2.0 and 4.0 -> 0xFFFF), screen origin, odd columns (upper word
//    half / wstrb 0xC), row pitch (1024-byte rows), screen corner (319,239),
//    and the coordinate rounding boundary at +/- 2^13 LSBs of the input
//    fixed-point domain (Q0.14);
//  - a random in-screen pixel stream with inter-pixel gaps;
//  - drain: every accepted pixel must produce exactly one matched AXI write
//    (scoreboard: addr / data / wstrb / bresp OKAY), checked via wait_drain
//    and the scoreboard queue-empty check in check_phase.
//
// The DUT's output_mem_offset_addr_i (and the scoreboard mirror) is set from
// the +MEM_OFFSET=<decimal bytes> plusarg (default 0), so regression runs the
// same test both at offset 0 and at a non-zero byte offset.
class tc_rop_backend_basic extends rop_backend_base_test;
  `uvm_component_utils(tc_rop_backend_basic)

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  // Integer pixel coordinate -> input fixed-point domain (14 fractional bits).
  local function logic [31:0] fq(int pixel);
    return 32'(pixel) << 14;
  endfunction

  task run_phase(uvm_phase phase);
    phase.raise_objection(this);

    // Wait for reset release, then give the DUT pipeline a breath.
    wait(env.in_agent.vif.rst_n === 1'b1);
    repeat(10) @(posedge env.in_agent.vif.clk);

    `uvm_info("TC_RB", "tc_rop_backend_basic starting (mem_offset=0x%0h)",
              env.scb.mem_offset)

    // --- 1. Directed pixels -----------------------------------------------------
    // Canonical contract vectors (Q13.14 intensity -> expected pixel16):
    //   0 (black, -27000 clamped) -> 0x0000   4096  (quarter)  -> 0x39C7
    //   8192 (half)               -> 0x7BCF   12288 (3/4)     -> 0xBDE7
    //   16384 (white)             -> 0xFFFF   32768 (2.0 OOD) -> 0xFFFF (saturated)
    // (a) Screen origin, half intensity.
    send_px(fq(0), fq(0), 32'sd8192);
    // (b) Quarter intensity at (5,3).
    send_px(fq(5), fq(3), 32'sd4096);
    // (c) SAME pixel with a negative intensity: color must clamp to 0x0000.
    send_px(fq(5), fq(3), -32'sd27000);
    // (d) SAME pixel with full-scale intensity: pure white 0xFFFF.
    send_px(fq(5), fq(3), 32'sd16384);
    // (e) Odd column -> upper half of the word, wstrb 0xC.
    send_px(fq(1), fq(0), 32'sd4096);
    // (f) Row pitch: (0,1) is one 1024-byte row below the origin pixel.
    send_px(fq(0), fq(1), 32'sd4096);
    // (g) Odd column in row 1 (both half-word and row pitch).
    send_px(fq(1), fq(1), 32'sd4096);
    // (h) Screen center, three-quarter intensity.
    send_px(fq(160), fq(120), 32'sd12288);
    // (i) Screen corner (319,239) — max x (odd) and max y; out-of-domain
    //     intensity 2.0 must saturate to 0xFFFF (no modulo wrap).
    send_px(fq(319), fq(239), 32'sd32768);
    // (j) Rounding boundary, round-up: x_i = 16.5 * 2^14 -> pixel 17.
    send_px(fq(16) + 16384, fq(20), 32'sd4096);
    // (k) Rounding boundary, round-down: x_i = 15.5 * 2^14 -> pixel 15.
    send_px(fq(16) - 16384, fq(20), 32'sd4096);

    // --- 2. Random in-screen stream (with inter-pixel gaps) ---------------------
    `uvm_info("TC_RB", "Driving 64-pixel random stream...", UVM_LOW)
    send_stream(.n(64), .gap_max(4));

    // --- 3. Drain: all 75 writes must have been matched by the scoreboard ------
    wait_drain(.timeout_cycles(200_000));

    repeat(20) @(posedge env.in_agent.vif.clk);
    `uvm_info("TC_RB", "tc_rop_backend_basic finished (scoreboard check_phase enforces drain)",
              UVM_LOW)
    phase.drop_objection(this);
  endtask

endclass

`endif
