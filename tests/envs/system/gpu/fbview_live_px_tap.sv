// fbview_live_px_tap.sv — passive per-pixel observer on the DUT's ROP raster path.
//
// A pixel observer module for the DUT's ROP raster path, attached at the tb
// scope (see the instance in tb_gpu.sv). Xcelium 20.09's xmelab rejects a
// `bind` onto `axil_rop_backend` in this two-stage flow (*E,CUVMUR):
// attach by tb-scope instance + hierarchical read instead — same passive
// semantics, no RTL edits. It observes the ROP pixel
// stream at the input-FIFO write boundary — exactly one clock of `infifo_winc`
// (= `rop_normalize_valid`) per pixel the DUT actually draws, with the
// normalized payload
//
//     infifo_wdata = { x(32), y(32), c(32) }
//
// where the value fields are x = 9 bits, y = 8 bits, and c = the 15-bit
// {cc,cc,cc} colour word (each zero-extended inside its 32-bit slot). This is
// the direct per-pixel source for the live fbview display: each item is
// (x, y, word) with `word` the full colour word as the C sink expects it
// (the C side applies the single documented `word & 0x1F` → grey rescale).
//
// Strictly passive: it reads signals only, drives nothing into the DUT,
// gates no clocks and is part of no handshake, so the golden scoreboard path
// is unaffected by its presence. It is a plain module + package (NO
// `uvm_pkg`) — the attach and the drain protocol stay outside any UVM
// context.
//
// Protocol: the bound instance appends to the package-scope bounded FIFO
// (fbview_live_px_pkg) once per drawn pixel; the drain side
// (tc_gpu_render_gui_live) pops items in order and forwards each to the fbview
// library. Single sim thread: the head is written only on DUT clock edges,
// the tail only by the drain task, and the drain `wait` resumes on the
// head/tail condition (that condition IS the wake-up source — no event is
// used).

`ifndef FBVIEW_LIVE_PX_TAP_SV
`define FBVIEW_LIVE_PX_TAP_SV

package fbview_live_px_pkg;
  // Bounded FIFO of "drawn pixels". Sized comfortably above one full frame
  // (76800 pixels) so the drain side never overflows even if it stalls for a
  // full render's worth of pushes. The tap wraps with head % FBSZ; in this
  // flow the drain side is always far behind head, so the wrap distance can
  // never collide with a live item.
  localparam int FBSZ = 200000;

  int          fifo_x    [FBSZ];
  int          fifo_y    [FBSZ];
  int unsigned fifo_word [FBSZ];   // full word handed to the C sink (low bits = {cc,cc,cc})

  longint      head;              // tap writes; +1 per observed pixel (no static initializer:
  longint      tail;              // xmvlog treats a static init as a second driver of an
                                  // always_ff output variable *E,MULAXX; ints default to 0)

  // Number of items currently queued (always >= 0 in this single-thread flow).
  function int count();
    return int'(head - tail);
  endfunction

  // Next item out (call only when count() > 0; in-order).
  function void pop (output int x, output int y, output int unsigned word);
    x     = fifo_x[int'(tail % FBSZ)];
    y     = fifo_y[int'(tail % FBSZ)];
    word  = fifo_word[int'(tail % FBSZ)];
    tail  = tail + 1;
  endfunction
endpackage

module fbview_live_px_tap (
  input  logic        clk,
  input  logic        px_valid,    // one pulse per drawn pixel
  input  logic [95:0] px_data     // { x(32), y(32), c(32) }
);
  always_ff @(posedge clk) begin
    if (px_valid) begin
      automatic longint i = fbview_live_px_pkg::head;
      fbview_live_px_pkg::fifo_x[int'(i % fbview_live_px_pkg::FBSZ)]    = int'(px_data[72:64]); // x  (9-bit value in a 32-bit slot)
      fbview_live_px_pkg::fifo_y[int'(i % fbview_live_px_pkg::FBSZ)]    = int'(px_data[40:32]); // y  (8-bit value in a 32-bit slot)
      fbview_live_px_pkg::fifo_word[int'(i % fbview_live_px_pkg::FBSZ)] = int'(px_data[14:0]);  // c  = {cc,cc,cc}
      fbview_live_px_pkg::head = i + 1;
    end
  end
endmodule

// NB: the attach point is the `u_fbview_live_px_tap` instance in tb_gpu.sv
// (tb-scope hierarchical read of this DUT-internal pair), NOT a `bind` here —
// the bind form failed Xcelium 20.09 elaboration (*E,CUVMUR). The bind-target
// signals it WOULD tap: `infifo_winc` (one pulse per drawn pixel) and
// `infifo_wdata` ({x(32), y(32), c(32)}) — both read by that instance.

`endif
