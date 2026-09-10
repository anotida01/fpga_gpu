// gpu_fbview_gui_pkg.sv — DPI-C import package for fbview's LIVE DISPLAY half.
//
// SV-side package mirroring the C-ABI display symbols in fbview/include/fbview.h
// (fbview_open / fbview_put_pixel / fbview_is_open / fbview_close), so UVM code
// can drive the live window per pixel without the DPI-C keyword appearing
// anywhere else in the repo.
//
// This half is for the live per-pixel push: the test drains the
// fbview_live_px_tap FIFO (one item per pixel the DUT drew) and forwards each
// to fbview_put_pixel. The whole-frame fbview_update path remains host-side
// only (the `gui_driver` host tool) — importing it here is not needed.
//
// Type map (per fbview.h, where `typedef unsigned int fbview_rc`):
//   fbview_rc       -> int unsigned
//   uint32_t        -> int unsigned
//   int             -> int
//   uint32_t*       -> output int unsigned (DPI-C pass-by-reference)
//   fbview_fmt      -> int (FBVIEW_FMT_15_GREY = 0)
//
// DPI-C note (xmvlog lesson, carried over): only DPI-legal simple types and
// no arrays cross the boundary — this package needs none (per-pixel calls are
// all scalar), so it is the cleanest possible surface.
//
// Return codes mirror fbview.h: FBVIEW_OK=0; FBVIEW_STATE_ERROR;
// FBVIEW_WINDOW_CLOSED (0x7003, the user closed the window);
// FBVIEW_FEATURE_UNAVAILABLE (0x7002, the lib was built without SDL2).
//
// This package intentionally does NOT emit UVM messages itself and does not
// import uvm_pkg — it has no UVM types. The caller (tc_gpu_render_gui_live)
// owns the reporting surface.

`ifndef GPU_FBVIEW_GUI_PKG
`define GPU_FBVIEW_GUI_PKG

package gpu_fbview_gui_pkg;

  // --- Error-code + format surface (mirrors fbview.h) ------------------------
  localparam int unsigned FBVIEW_OK                  = 32'h0;
  localparam int unsigned FBVIEW_OOM                 = 32'h1;
  localparam int unsigned FBVIEW_STATE_ERROR         = 32'h3;
  localparam int unsigned FBVIEW_FEATURE_UNAVAILABLE = 32'h7002; // built without SDL2
  localparam int unsigned FBVIEW_WINDOW_CLOSED       = 32'h7003; // user closed the window
  localparam int unsigned FBVIEW_FMT_15_GREY         = 32'h0;    // sole input format

  // --- DPI-C imports: the four C-ABI display symbols from fbview.h -----------
  // word: the DUT's full framebuffer word passed verbatim (int unsigned); the
  // C side applies the single documented transform (word & 0x1F) -> grey.
  import "DPI-C" function int unsigned fbview_open (
      input  int            w,
      input  int            h,
      input  int            fmt,
      output int unsigned   out_handle);

  import "DPI-C" function int unsigned fbview_put_pixel (
      input  int unsigned   handle,
      input  int            x,
      input  int            y,
      input  int unsigned   word);

  import "DPI-C" function int unsigned fbview_is_open (
      input  int unsigned   handle);

  import "DPI-C" function int unsigned fbview_close (
      input  int unsigned   handle);

  // --- Thin wrappers ---------------------------------------------------------

  // Open a live window (FBVIEW_FMT_15_GREY only; the other formats are not
  // part of this ABI surface) and return the library handle.
  function int unsigned fbview_open_win (input int w, input int h,
                                         output int unsigned handle);
    return fbview_open(w, h, int'(FBVIEW_FMT_15_GREY), handle);
  endfunction

  // Push one drawn pixel (x, y in [0,w)x[0,h); word = DUT word).
  function int unsigned fbview_push_px (input int unsigned handle,
                                        input int x, input int y,
                                        input int unsigned word);
    return fbview_put_pixel(handle, x, y, word);
  endfunction

endpackage

`endif
