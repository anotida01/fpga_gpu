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

/* Return the 15-bit {cc,cc,cc} grey word for pixel (x,y). */
cmodel_rc cmodel_fb_pixel(int x, int y);

/* Return the raw 32-bit Q4.13 z-buffer value at (x,y). */
cmodel_rc cmodel_z_pixel(int x, int y);

/* Free and re-initialize all global state (so the next triple is clean). */
cmodel_rc cmodel_reset(void);

 /* Run the self-test golden and return 0 on match, non-zero on mismatch. */
 cmodel_rc cmodel_selftest(void);

 /* Return the ABI major version (1) for the DPI-C caller to sanity-check. */
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
