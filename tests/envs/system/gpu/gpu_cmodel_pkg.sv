// gpu_cmodel_pkg.sv — DPI-C import package for the cmodel_golden shared library.
//
// SV-side package mirroring the 8
// C-ABI symbols in c_model/include/cmodel_golden.h so UVM code can call into
// the C-model golden reference without the DPI-C keyword appearing anywhere
// else in the repo.
//
// Type map (per cmodel_golden.h, where `typedef unsigned int cmodel_rc`):
//   cmodel_rc      -> int unsigned
//   int            -> int
//   const char*    -> input string
//
// Error codes mirror c_model/src/cmodel_golden.cpp:22-26 (CMODEL_OK=0 on
// success; non-zero = a specific C-side error; the caller decides how to
// surface / escalate).
//
// This package intentionally does NOT emit UVM_ERROR itself; the caller
// (gpu_scoreboard / tc_gpu_render_golden) owns the reporting surface so the
// package stays a thin, testable wrapper over the C-ABI. It also does not
// import uvm_pkg — it has no UVM types, classes, or macros.

`ifndef GPU_CMODEL_PKG
`define GPU_CMODEL_PKG

package gpu_cmodel_pkg;

  // --- Error-code surface (mirrors cmodel_golden.cpp:22-26) -----------------
  localparam int unsigned CMODEL_OK            = 32'h0;
  localparam int unsigned CMODEL_OOM           = 32'h1;
  localparam int unsigned CMODEL_FILE_ERROR    = 32'h2; // mesh path did not resolve under xrun CWD
  localparam int unsigned CMODEL_STATE_ERROR   = 32'h3;
  localparam int unsigned CMODEL_SELFTEST_NI   = 32'h7001; // self-test golden not yet implemented

  // --- DPI-C imports: 8 C-ABI symbols from cmodel_golden.h ------------------
  import "DPI-C" function int unsigned cmodel_init (input int w, input int h);
  import "DPI-C" function int unsigned cmodel_load_mesh (input string memh_path);
  import "DPI-C" function int unsigned cmodel_render ();
  import "DPI-C" function int unsigned cmodel_fb_pixel (input int x, input int y);
  import "DPI-C" function int unsigned cmodel_z_pixel (input int x, input int y);
  import "DPI-C" function int unsigned cmodel_reset ();
  import "DPI-C" function int unsigned cmodel_selftest ();
  import "DPI-C" function int unsigned cmodel_version ();

  // --- Wrapper tasks --------------------------------------------------------

  // "Did the DPI-C link actually resolve?" sanity gate: 1 iff the C model
  // reports ABI major version 1 (the value declared in cmodel_golden.h:39).
  // The scoreboard / test should call this once at entry and uvm_fatal on 0
  // before trusting any cmodel_* result.
  function bit cmodel_version_ok();
    return (cmodel_version() == 1);
  endfunction

  // Run the full pipeline (reset -> init -> load -> render) in one call.
  // Returns CMODEL_OK on success, the specific non-OK C error code otherwise.
  // Defaults (320 x 240) match the C model's fixed V_SIZE/H_SIZE (cmodel_core.h)
  // and the DUT's ROP_BUF_WIDTH/HEIGHT (gpu_base_test.sv); pass explicit w/h if
  // the DUT framebuffer dimensions change and the C model follows.
  function int unsigned cmodel_run(input string memh,
                                   input int      w = 320,
                                   input int      h = 240);
    int unsigned rc;
    rc = cmodel_reset();
    if (rc != CMODEL_OK) return rc;
    rc = cmodel_init(w, h);
    if (rc != CMODEL_OK) return rc;
    rc = cmodel_load_mesh(memh);
    if (rc != CMODEL_OK) return rc;
    rc = cmodel_render();
    if (rc != CMODEL_OK) return rc;
    return CMODEL_OK;
  endfunction

  // Compare a DUT framebuffer (indexed [y*w + x]) against the C-model's own
  // FRAMEBUFFER via cmodel_fb_pixel, over w*h pixels.
  //
  // The caller MUST have already succeeded with cmodel_run() before calling
  // this — a non-OK return from cmodel_run() means the C model did not
  // render, so there is nothing to compare against.
  //
  // Returns the pure mismatch count (0 == full match, max w*h). This
  // function never returns a C error code.
  //
  // Caller is expected to report the first mismatched (x, y, expected,
  // actual) plus the aggregate count in its own UVM_ERROR / UVM_INFO; this
  // function emits no UVM-level message.
  function int unsigned cmodel_check_golden(input logic [31:0] dut_fb[],
                                            input int          w = 320,
                                            input int          h = 240);
    int unsigned mismatch;
    int unsigned expected, actual;
    int          x, y;
    mismatch = 0;
    for (y = 0; y < h; y++) begin
      for (x = 0; x < w; x++) begin
        expected = cmodel_fb_pixel(x, y);
        actual   = dut_fb[y*w + x];
        if (expected !== actual)
          mismatch = mismatch + 1;
      end
    end
    return mismatch;
  endfunction

endpackage

`endif
