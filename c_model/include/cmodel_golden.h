/*
 * cmodel_golden.h - public C-ABI for the cmodel_golden shared library.
 *
 * Phase A (item 3.1) only requires these symbols to be visible in the .so so
 * that Phase B can `import "DPI-C"` them from UVM. The stubs below return 0
 * for now and will be implemented in Phase A items 3.2-3.9.
 */
#ifndef CMODEL_GOLDEN_H
#define CMODEL_GOLDEN_H

#ifdef __cplusplus
extern "C" {
#endif

typedef unsigned int cmodel_rc;   /* error codes (0 == OK) */

/* Public return-code values (see per-function doc comments for the set each
 * function can emit). All other values are reserved for future extensions. */
enum {
    CMODEL_OK                     = 0,     /* success */
    CMODEL_OOM                    = 1,     /* allocation failure */
    CMODEL_FILE_ERROR             = 2,     /* file I/O failure */
    CMODEL_STATE_ERROR            = 3,     /* required state not initialized */
    CMODEL_SELFTEST_NI            = 0x7001,/* self-test not implemented (stub) */
    CMODEL_FEATURE_UNAVAILABLE    = 0x7002 /* feature compiled out (e.g. PNG) */
};

/* Allocate the framebuffer and z-buffer; initialize matrices to identity. */
cmodel_rc cmodel_init(int w, int h);

/* Parse a .memh mesh file into OBJ (16 mat + 3 light + 1 count + N*7 words). */
cmodel_rc cmodel_load_mesh(const char *memh_path);

/* Run the pipeline: xform OBJ -> shade -> draw into FRAMEBUFFER + Z_BUFFER. */
cmodel_rc cmodel_render(void);

/* Return the 16-bit RGB565 grey word for pixel (x,y), carried in [15:0]:
 *     L  = saturating clamp of floor(raw*31/2^14) to [0,31] (Q13.14 shaded value);
 *     G6 = {L[4:0], L[4]}   (standard MSB replication into the 6-bit green);
 *     pixel16 = {L, G6, L}  ->  black 0x0000, white 0xFFFF.
 * Supersedes the earlier 15-bit 5-5-5 {cc,cc,cc} packing. */
cmodel_rc cmodel_fb_pixel(int x, int y);

/* Return the 5-bit grey intensity L in [0,31] for pixel (x,y) - format-agnostic
 * intensity query (same saturating clamp as cmodel_fb_pixel). */
cmodel_rc cmodel_fb_gray(int x, int y);

/* Return the raw 32-bit Q4.13 z-buffer value at (x,y). */
cmodel_rc cmodel_z_pixel(int x, int y);

/* Per-vertex directional diffuse, EXACT variant (unit-level oracle).
 *   Inputs: light (lx,ly,lz) and normal (nx,ny,nz), each a 27-bit
 *   two's-complement Q13.14 raw value (precondition: |v| < 2^26).
 *   Math:   sum = nx*lx + ny*ly + nz*lz   (int64, exact products)
 *           out = (int32_t)((sum >> 14) & 0x7FFFFFF)  // arithmetic floor
 *                                                          shift, 27-bit
 *   Returns the 27-bit Q13.14 result, sign-extended into the low 32 bits
 *   (i.e. the value you would read from a 27-bit two's-complement port).
 *   Stateless: valid without cmodel_init / cmodel_load_mesh.
 *
 *   Relationship to the per-term-rounded dot_3 (frame-level path): dot_3
 *   multiplies each component pair through fpm::fixed (round-to-nearest
 *   per product) and adds the three rounded terms; this function
 *   accumulates exact int64 products and applies ONE arithmetic floor
 *   shift. The two agree whenever every product is exact (e.g. unit
 *   normals) and can differ by 1-2 LSB on general data. Worked example
 *   under the box light (10711, -10081, 7217):
 *     (-16384, 0, 0)  -> -10711   (both variants)
 *     (8192,8192,8192)-> exact 3923 (floor(3923.5));
 *                         per-term-rounded 3924 (5356 - 5041 + 3609)
 *   The per-term-rounded path stays the locked frame-level behaviour
 *   (colour contract); do NOT "align" one variant to the other.
 */
int cmodel_shade_dot_exact(int lx, int ly, int lz,
                           int nx, int ny, int nz);

/* Flat vertex count: 3 * (triangle count in the loaded mesh).
 *   Returns 0 if no mesh is loaded. */
int cmodel_vertex_count(void);

/* Raw mesh vertex i (0-based, i < cmodel_vertex_count()):
 *   pos[4] = x,y,z,w ; nrm[3] = xn,yn,zn
 *   32-bit two's-complement Q13.14 raw values, as loaded.
 *   Flat indexing: vertex i = triangle i/3, corner i%3 (p0,p1,p2 order),
 *   matching the DUT stream order. Out-of-range index -> CMODEL_STATE_ERROR.
 *   Precondition: cmodel_load_mesh succeeded (else CMODEL_STATE_ERROR). */
cmodel_rc cmodel_get_vertex_raw(int i, int pos[4], int nrm[3]);

/* Transformed (raster-space) vertex i: pos[4] = x,y,z,w (the 4x4 composite
 *   transform + w-normalization applied during cmodel_render; the C model
 *   does not transform normals).
 *   Flat indexing as cmodel_get_vertex_raw; out-of-range -> CMODEL_STATE_ERROR.
 *   Precondition: cmodel_render succeeded (else CMODEL_STATE_ERROR). */
cmodel_rc cmodel_get_vertex_xform(int i, int pos[4]);

/* Rendered per-vertex shaded intensity (Q13.14, the value shade_obj stored
 *   in colour.red - i.e. the per-term-rounded dot_3 result). For
 *   frame-level consistency checks; use cmodel_shade_dot_exact(light, nrm)
 *   for the unit-level exact oracle.
 *   Flat indexing as cmodel_get_vertex_raw.
 *   Precondition: cmodel_render succeeded; returns 0 if not rendered or
 *   out of range (int return has no error channel). */
int cmodel_get_vertex_shade(int i);

/* Write a mesh file in the 16+3+1+N*7 format (8-hex-digit lines,
 *   two's-complement raw values): 16 matrix words (mat), 3 light words
 *   (light), 1 count word (= n_vertices*7), then n_vertices*7 words with
 *   each vertex = (x,y,z,w,nx,ny,nz). Round-trips with cmodel_load_mesh.
 *   Returns CMODEL_OK / CMODEL_FILE_ERROR. */
cmodel_rc cmodel_write_mesh(const char *path,
                            const int mat[16], const int light[3],
                            const int verts[], int n_vertices);

/* Free and re-initialize all global state (so the next triple is clean). */
cmodel_rc cmodel_reset(void);

 /* Run the self-test golden (known-answer checks: exact-dot vectors,
  * exact-vs-rounded divergence, seeded consistency sweep, write/load mesh
  * round-trip). Self-contained: no repo-relative file reads, no
  * framebuffer; valid before cmodel_init. Returns 0 on full match,
  * non-zero (bitmask of the failed sub-checks) otherwise. */
 cmodel_rc cmodel_selftest(void);

 /* Return the ABI major version (3) for the DPI-C caller to sanity-check.
  * 1 = original 9-symbol frame-level surface; 2 = adds cmodel_shade_dot_
  * exact, the per-vertex queries, and cmodel_write_mesh (additive);
  * 3 = adds seven pure stage oracles + cmodel_get_matrix (additive). */
 cmodel_rc cmodel_version(void);

 /* =========================================================================
  * ABI v3: Seven pure, stateless stage oracles + stateful matrix query
  * ========================================================================= */

 /* Per-row 4x4 transform, pre-w-norm, DUT madd arithmetic.
  *   Inputs: mat[16] (row-major m11..m44) + pos[4] (x,y,z,w 27-bit patterns Q12.14).
  *   Output: pos_o[4] (transformed x,y,z,w 27-bit patterns).
  *   Math: row r: acc = sum_k s27(mat[r*4+k]) * s27(pos[k]); pos_o[r] = acc >> 14, 27-bit wrap.
  *   Precondition: |acc| < 2^53 for meaningful (non-wrapped) results.
  *   Divergence vs cmodel_get_vertex_xform (fpm per-term rounded, post
  *   w-norm - comparable only on w == 1 data): <= 4 LSB/component
  *   (selftest 6H(a), seed 0xC0FFEE, N = 1026: measured max 2).
  *   Stateless: valid without cmodel_init / cmodel_load_mesh. */
 cmodel_rc cmodel_vertex_xform_exact(const int mat[16], const int pos[4], int pos_o[4]);

 /* Per-component perspective divide, DUT LPM semantics (LPM_REMAINDERPOSITIVE=TRUE).
  *   Inputs: vertex component patterns x, y, z, w (27-bit Q12.14).
  *   Output: out[4] = transformed (x,y,z) 27-bit patterns + out[3] = 1<<14 (constant w_o).
  *   Precondition: w != 0 (else CMODEL_STATE_ERROR).
  *   Divergence vs fpm round-to-nearest divide: <= 1 raw LSB/component
  *   (proven: both quotients in {floor, ceil} of the exact rational;
  *   selftest 6H(b), seed 0xC0FFEE, N = 1024: measured max 1, sharp). */
 cmodel_rc cmodel_w_norm_exact(int x, int y, int z, int w, int out[4]);

 /* v_cw A-form winding value, DUT as-written (unsigned-pattern semantics F9).
  *   Inputs: triangle coordinates (x0,y0, x1,y1, x2,y2) as 27-bit patterns.
  *   Returns: 32-bit signed registered winding value val. */
 int cmodel_tri_winding(int x0, int y0, int x1, int y1, int x2, int y2);

 /* edge_func B-form, DUT as-written (unsigned-pattern semantics F9).
  *   Inputs: edge definition and test point (x0,y0, x1,y1, x2,y2) as 27-bit patterns.
  *   Returns: 32-bit signed edge value. */
 int cmodel_edge_func(int x0, int y0, int x1, int y1, int x2, int y2);

 /* Per-vertex 1/z, DUT LPM semantics (numer = 1<<28, denom = z).
  *   Input: z (27-bit pattern). Output: *out (32-bit Q14.14 FIFO word).
  *   Precondition: z != 0 (else CMODEL_STATE_ERROR). */
 cmodel_rc cmodel_inv_z_exact(int z, int *out);

 /* Per-sample depth datapath (wx_div + get_depth + inv_z_div).
  *   Inputs: raw edges (e0,e1,e2), area, iz0, iz1, iz2 (27-bit truncated iz).
  *   Outputs: w[3], one_over_z, z_depth. */
 cmodel_rc cmodel_depth_sample(int e0, int e1, int e2, int area,
                               int iz0, int iz1, int iz2,
                               int w[3], int *one_over_z, int *z_depth);

 /* One sub-pixel sample of the raster datapath (edges + HP + depth).
  *   Inputs: triangle in post-swap vertex order, iz0..iz2, sample point (px,py).
  *   Outputs: inside (0/1 inclusive), w[3], one_over_z, z_depth. */
 cmodel_rc cmodel_raster_sample(int x0, int y0, int x1, int y1, int x2, int y2,
                                int iz0, int iz1, int iz2,
                                int px, int py,
                                int *inside, int w[3], int *one_over_z, int *z_depth);

 /* Stateful matrix consistency query.
  *   Output: mat[16] (raw values of loaded COMP_XFORM_MAT, row-major).
  *   Precondition: cmodel_load_mesh succeeded (else CMODEL_STATE_ERROR). */
 cmodel_rc cmodel_get_matrix(int mat[16]);

 /* Write the rendered FRAMEBUFFER to `path` as a (H_SIZE x V_SIZE) 8-bit
  * greyscale PNG image.  Off-sim helper only - NOT on the DPI-C golden path.
  *
  * Per-pixel formula (matches render_gui.py --save exactly, bit-exact with C1):
  *     int32_t raw = FRAMEBUFFER[y][x].red.raw_value();   // Q13.14
  *     int32_t cc  = (raw * 31) >> 14;                     // floor, 0..31 (or negative)
  *     if (cc < 0) cc = 0;
  *     if (cc > 31) cc = 31;
  *     out = (uint8_t)((cc * 255) / 31);                  // 8-bit greyscale
  *
  * The file is written as a top-down row-major (y-major) PNG, colortype 2 (RGB,
  * three identical channels) - portable to viewers without greyscale handling.
  *
  * Precondition: cmodel_init + cmodel_load_mesh + cmodel_render have succeeded
  * (i.e. FRAMEBUFFER is non-NULL and contains rendered pixels).
  *
  * Return codes:
  *   0                        written successfully.
  *   CMODEL_STATE_ERROR       framebuffer not allocated or empty (no cmodel_render yet).
  *   CMODEL_FILE_ERROR        fopen/fwrite/png-write failure.
  *   CMODEL_FEATURE_UNAVAILABLE  the shared lib was built WITHOUT libpng support
  *                              (build-time feature gate, see CMakeLists.txt).
  */
 cmodel_rc cmodel_save_image(const char *path);

#ifdef __cplusplus
}
#endif

#endif
