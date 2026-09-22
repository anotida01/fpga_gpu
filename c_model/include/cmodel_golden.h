/*
 * cmodel_golden.h — public C-ABI for the cmodel_golden shared library.
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

/* Return the 5-bit grey intensity L in [0,31] for pixel (x,y) — format-agnostic
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
 *   in colour.red — i.e. the per-term-rounded dot_3 result). For
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

 /* Return the ABI major version (2) for the DPI-C caller to sanity-check.
  * 1 = original 9-symbol frame-level surface; 2 = adds cmodel_shade_dot_
  * exact, the per-vertex queries, and cmodel_write_mesh (additive). */
 cmodel_rc cmodel_version(void);

 /* Write the rendered FRAMEBUFFER to `path` as a (H_SIZE x V_SIZE) 8-bit
  * greyscale PNG image.  Off-sim helper only — NOT on the DPI-C golden path.
  *
  * Per-pixel formula (matches render_gui.py --save exactly, bit-exact with C1):
  *     int32_t raw = FRAMEBUFFER[y][x].red.raw_value();   // Q13.14
  *     int32_t cc  = (raw * 31) >> 14;                     // floor, 0..31 (or negative)
  *     if (cc < 0) cc = 0;
  *     if (cc > 31) cc = 31;
  *     out = (uint8_t)((cc * 255) / 31);                  // 8-bit greyscale
  *
  * The file is written as a top-down row-major (y-major) PNG, colortype 2 (RGB,
  * three identical channels) — portable to viewers without greyscale handling.
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
