// cmodel_query_pkg.sv - DPI-C import package for the per-vertex query
// surface of the cmodel_golden shared library.
//
// SV-side package mirroring the per-vertex C-ABI symbols in
// c_model/include/cmodel_golden.h (ABI major version 2) so unit-level envs
// can call the C-model reference without the DPI-C keyword appearing
// anywhere else in the repo. Frame-level surface (cmodel_run,
// cmodel_fb_pixel, ...) stays in gpu_cmodel_pkg; this package is the
// standalone, unit-level oracle surface:
//
//   cmodel_version          ABI major version (2)
//   cmodel_shade_dot_exact  pure exact-shade reference (stateless)
//   cmodel_vertex_count     flat vertex count of the loaded mesh
//   cmodel_get_vertex_raw   raw (x,y,z,w,nx,ny,nz) of vertex i
//   cmodel_get_vertex_xform transformed (x,y,z,w) of vertex i (post-render)
//   cmodel_get_vertex_shade rendered per-vertex shade of vertex i (post-render)
//
// Type map (per cmodel_golden.h, where `typedef unsigned int cmodel_rc`):
//   cmodel_rc      -> int unsigned
//   int            -> int
//   const char*    -> input string
//
// Error codes mirror cmodel_golden.h: CMODEL_OK=0 on success; non-zero = a
// specific C-side error; the caller decides how to surface / escalate.
//
// This package intentionally does NOT emit UVM_ERROR itself; the caller
// (the consuming env / test) owns the reporting surface so the package
// stays a thin, testable wrapper over the C-ABI. It also does not import
// uvm_pkg - it has no UVM types, classes, or macros. The mesh writer
// (cmodel_write_mesh) is host-only and deliberately NOT imported.

`ifndef CMODEL_QUERY_PKG
`define CMODEL_QUERY_PKG

package cmodel_query_pkg;

  // --- Error-code surface (mirrors cmodel_golden.h) ------------------------
  localparam int unsigned CMODEL_OK         = 32'h0;
  localparam int unsigned CMODEL_OOM        = 32'h1;
  localparam int unsigned CMODEL_FILE_ERROR = 32'h2;
  localparam int unsigned CMODEL_STATE_ERROR = 32'h3;

  // --- DPI-C imports: per-vertex query surface (ABI v2) --------------------
  import "DPI-C" function int unsigned cmodel_version ();

  // Exact per-vertex directional diffuse: int64-exact 3-term sum, one
  // arithmetic floor shift, 27-bit two's-complement result sign-extended
  // into the low 32 bits. Stateless - valid without cmodel_load_mesh.
  import "DPI-C" function int cmodel_shade_dot_exact (input int lx, input int ly, input int lz,
                                                      input int nx, input int ny, input int nz);

  import "DPI-C" function int cmodel_vertex_count ();

  // Raw mesh vertex i (pos[4] = x,y,z,w; nrm[3] = xn,yn,zn) - 32-bit
  // two's-complement Q13.14 raw values as loaded. Precondition:
  // cmodel_load_mesh succeeded (else CMODEL_STATE_ERROR).
  import "DPI-C" function int unsigned cmodel_get_vertex_raw (input int idx,
                                                              output int pos[4],
                                                              output int nrm[3]);

  // Transformed (raster-space) vertex i (pos[4] = x,y,z,w). Precondition:
  // cmodel_render succeeded (else CMODEL_STATE_ERROR).
  import "DPI-C" function int unsigned cmodel_get_vertex_xform (input int idx,
                                                                output int pos[4]);

  // Rendered per-vertex shaded intensity (Q13.14, the per-term-rounded
  // dot_3 result stored in colour.red). Returns 0 if not rendered or
  // out of range (int return has no error channel).
  import "DPI-C" function int cmodel_get_vertex_shade (input int idx);

  // --- DPI-C imports: seven pure stage oracles + cmodel_get_matrix (ABI v3) ---
  import "DPI-C" function int unsigned cmodel_vertex_xform_exact (input int mat[16],
                                                                 input int pos[4],
                                                                 output int pos_o[4]);
  import "DPI-C" function int unsigned cmodel_w_norm_exact (input int x,
                                                           input int y,
                                                           input int z,
                                                           input int w,
                                                           output int out[4]);
  import "DPI-C" function int cmodel_tri_winding (input int x0, input int y0,
                                                  input int x1, input int y1,
                                                  input int x2, input int y2);
  import "DPI-C" function int cmodel_edge_func (input int x0, input int y0,
                                                input int x1, input int y1,
                                                input int x2, input int y2);
  import "DPI-C" function int unsigned cmodel_inv_z_exact (input int z,
                                                           output int out_z);
  import "DPI-C" function int unsigned cmodel_depth_sample (input int e0, input int e1, input int e2,
                                                             input int area,
                                                             input int iz0, input int iz1, input int iz2,
                                                             output int w[3],
                                                             output int one_over_z,
                                                             output int z_depth);
  import "DPI-C" function int unsigned cmodel_raster_sample (input int x0, input int y0,
                                                               input int x1, input int y1,
                                                               input int x2, input int y2,
                                                               input int iz0, input int iz1, input int iz2,
                                                               input int px, input int py,
                                                               // `inside` is a reserved SV keyword; DPI-C binds by
                                                               // position, so the local arg name may differ from C.
                                                               output int is_inside,
                                                               output int w[3],
                                                               output int one_over_z,
                                                               output int z_depth);
  import "DPI-C" function int unsigned cmodel_get_matrix (output int mat[16]);

  // --- Wrapper functions ----------------------------------------------------

  // "Did the DPI-C link actually resolve, and is it the right ABI?" sanity
  // gate: 1 iff the C model reports ABI major version 3. The consumer
  // should call this once at entry and uvm_fatal on 0 before trusting any
  // cmodel_* result.
  function bit cmodel_version_ok();
    return (cmodel_version() == 3);
  endfunction

endpackage

`endif
