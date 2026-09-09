// gpu_fbview_pkg.sv — DPI-C import package for the fbview shared library.
//
// SV-side package mirroring the C-ABI symbol in fbview/include/fbview.h so UVM
// code can serialise the DUT's framebuffer buffer to a viewable PNG without the
// DPI-C keyword appearing anywhere else in the repo.
//
// Type map (per fbview.h, where `typedef unsigned int fbview_rc`):
//   fbview_rc     -> int unsigned
//   int           -> int
//   const char*   -> input string
//   const uint16_t* (one 16-bit word per pixel)
//                  -> input shortint unsigned data[76800]
//                     (fixed-size unpacked array of 16-bit `shortint unsigned`).
//                     DPI-C maps `shortint unsigned` -> C `unsigned short` ==
//                     uint16_t, and passes a pointer to the first element, so C
//                     consumes it exactly like an array of uint16_t.)
//   fbview_fmt (enum, FBVIEW_FMT_15_GREY = 0)
//                  -> input int (the enum value)
//
// DPI-C note: xmvlog only accepts DPI-legal simple types (int/shortint/byte/...)
// and fixed-size (not unbounded) unpacked arrays across the boundary, so the
// element type is shortint unsigned (16-bit, matching uint16_t) and the array
// is a fixed-size [76800] (the DUT framebuffer = 320 x 240 pixels). The C side
// only reads the w*h elements it is told to, so the fixed bound is harmless.
//
// The DUT framebuffer the test readbacks is one 32-bit word per pixel
// (logic [31:0] dut_fb[], low 15 bits = the {cc,cc,cc} pixel). The wrapper
// below narrows each word to [15:0] before crossing the DPI boundary.
//
// Error codes mirror fbview.h (FBVIEW_OK=0 on success; non-zero = a specific
// C-side error). FBVIEW_FEATURE_UNAVAILABLE (0x7002) means the shared library
// was built without libpng — expected when the build was in STUB mode.
//
// This package intentionally does NOT emit UVM messages itself; the caller
// (tc_gpu_render_golden) owns the reporting surface. It also does not import
// uvm_pkg — it has no UVM types, classes, or macros.

`ifndef GPU_FBVIEW_PKG
`define GPU_FBVIEW_PKG

package gpu_fbview_pkg;

  // --- Error-code + format surface (mirrors fbview.h) ------------------------
  localparam int unsigned FBVIEW_OK                  = 32'h0;
  localparam int unsigned FBVIEW_OOM                 = 32'h1;
  localparam int unsigned FBVIEW_FILE_ERROR          = 32'h2;
  localparam int unsigned FBVIEW_STATE_ERROR         = 32'h3;
  localparam int unsigned FBVIEW_FEATURE_UNAVAILABLE = 32'h7002; // built without libpng (STUB)
  localparam int unsigned FBVIEW_FMT_15_GREY         = 32'h0;    // sole input format in v1
  // DUT framebuffer geometry (320 x 240): the DPI-C unpacked array must be a
  // FIXED size (xmvlog rejects an unbounded one across the boundary); 76800 is
  // one {cc,cc,cc} word per pixel. The C side only reads the w*h it is told.
  localparam int unsigned FBVIEW_FB_WORDS = 320 * 240;

  // --- DPI-C import: the single C-ABI symbol from fbview.h ------------------
  // data: fixed-size unpacked array of 16-bit shortint unsigned (== C unsigned
  // short == uint16_t). DPI passes a pointer to the first element, so C consumes
  // it as uint16_t[N] and only reads the w*h words it is told. The bound is the
  // integer literal 76800 (320 x 240) so the bound is unambiguous to the DPI
  // importer (xmvlog rejects an unbounded array across the boundary).
  import "DPI-C" function int unsigned fbview_save_png (
      input string            path,
      input int               w,
      input int               h,
      input shortint unsigned data[76800],
      input int               fmt);

  // --- Wrapper tasks ---------------------------------------------------------

  // Serialise the DUT readback framebuffer (32-bit words) to a PNG at `path`.
  // Narrows each word to its low-16 (the {cc,cc,cc} pixel) into a fixed-size
  // 16-bit buffer and calls the C library with FBVIEW_FMT_15_GREY.
  //
  //   dut_fb[]  one 32-bit word per pixel, row-major, index [y*W + x] (W = w)
  //   w, h      framebuffer geometry (defaults match the DUT 320 x 240)
  //
  // Returns FBVIEW_OK (0) on success, the specific non-OK C error code
  // otherwise (e.g. FBVIEW_FEATURE_UNAVAILABLE when the lib is a no-libpng stub).
  // The caller reports / escalates the return code — this emits no UVM message.
  function int unsigned fbview_save_dut (input string      path,
                                         input logic [31:0] dut_fb[],
                                         input int         w = 320,
                                         input int         h = 240);
    shortint unsigned fb16[FBVIEW_FB_WORDS];
    int n;
    n = w * h;
    for (int i = 0; i < n; i++)
      fb16[i] = dut_fb[i][15:0];   // 15-bit {cc,cc,cc} pixel (bit 15 is 0)
    return fbview_save_png(path, w, h, fb16, FBVIEW_FMT_15_GREY);
  endfunction

endpackage

`endif
