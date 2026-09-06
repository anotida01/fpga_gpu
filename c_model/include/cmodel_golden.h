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

#ifdef __cplusplus
}
#endif

#endif
