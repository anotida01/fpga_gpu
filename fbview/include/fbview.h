/*
 * fbview.h — public C-ABI for the fbview shared library (v1).
 *
 * v1 exports exactly one symbol, fbview_save_png: serialize a raw framebuffer
 * buffer in a known format to a viewable PNG. A live-GUI extension may add
 * further symbols to this same header later; none are part of v1.
 *
 * C-ABI clean: this header compiles as both C and C++. All return codes are the
 * fixed enum below; no other value is returned by any fbview_* symbol.
 */
#ifndef FBVIEW_H
#define FBVIEW_H

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef unsigned int fbview_rc;   /* return codes (0 == OK) */

/* Public return-code enum. All values are reserved; no fbview_* symbol returns
 * any value other than these five. */
enum {
    FBVIEW_OK                     = 0,
    FBVIEW_OOM                    = 1,
    FBVIEW_FILE_ERROR             = 2,
    FBVIEW_STATE_ERROR            = 3,
    FBVIEW_FEATURE_UNAVAILABLE    = 0x7002
};

/* Input formats. v1 accepts exactly one (15-bit {cc,cc,cc} grey words in a
 * uint16_t[w*h] array). More formats (Q13.14 raw, 8-bit RGB, ...) can be added
 * as future extensions without breaking this ABI — consumers already switch on
 * `fmt` at call time. */
typedef enum { FBVIEW_FMT_15_GREY = 0 } fbview_fmt;

/*
 * Serialize a raw framebuffer buffer to a PNG at `path`.
 *
 *   fmt = FBVIEW_FMT_15_GREY:
 *     data[w*h] of uint16_t, where data[y*w + x] is the 15-bit {cc,cc,cc} word
 *     (bits [4:0]=R=cc, [9:5]=G=cc, [14:10]=B=cc) as emitted by the DUT's ROP
 *     backend and as read back by the UVM scoreboard.
 *     Per-pixel output formula: int32_t cc = (word & 0x1F); out = (uint8_t)(cc * 255 / 31).
 *     The PNG is written as 8-bit RGB (colortype 2) with the three channels identical,
 *     top-down row-major, so the bytes are viewable in any standard viewer.
 *
 * Precondition: data must be a valid pointer to w*h uint16_t; w,h >= 1.
 *
 * Return codes:
 *   FBVIEW_OK                       written successfully.
 *   FBVIEW_OOM                      malloc failure on the intermediate byte row buffer.
 *   FBVIEW_STATE_ERROR              bad args (NULL path / empty path / NULL data / w<=0 / h<=0).
 *   FBVIEW_FILE_ERROR               fopen / png write failure.
 *   FBVIEW_FEATURE_UNAVAILABLE      shared lib was built WITHOUT libpng (see CMakeLists.txt /
 *                                   Makefile).
 */
fbview_rc fbview_save_png(const char *path, int w, int h,
                          const uint16_t *data, fbview_fmt fmt);

#ifdef __cplusplus
}
#endif

#endif
