/*
 * fbview.h — public C-ABI for the fbview shared library (v1).
 *
 * Symbol set (current release):
 *   - fbview_save_png: serialize a raw framebuffer buffer to a viewable PNG.
 *   - fbview_open / fbview_update / fbview_is_open / fbview_close: live-GUI
 *     display of the same buffer format (optional SDL2 backend; absent at
 *     build time the four symbols are still exported and return
 *     FBVIEW_FEATURE_UNAVAILABLE).
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
 * any value other than these six. */
enum {
    FBVIEW_OK                     = 0,
    FBVIEW_OOM                    = 1,
    FBVIEW_FILE_ERROR             = 2,
    FBVIEW_STATE_ERROR            = 3,
    FBVIEW_FEATURE_UNAVAILABLE    = 0x7002,
    FBVIEW_WINDOW_CLOSED          = 0x7003   /* live display: window closed by the user */
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

/*
 * fbview_open / fbview_update / fbview_close / fbview_is_open — live GUI display.
 *
 * All four operate on a "handle" that identifies a live window + renderer +
 * texture triple in the library's internal state. The host's lifecycle is:
 *   1. fbview_open(w, h, FBVIEW_FMT_15_GREY, &handle)   — once per program
 *   2. fbview_update(handle, frame)                      — once per frame
 *   3. fbview_is_open(handle)                            — poll each frame
 *   4. fbview_close(handle)                              — once at program end
 *
 * The window is a fixed-size (w x h pixels, title "fbview WxH"), NOT
 * resizable (a resizable window would change the blit scaling and break the
 * "render exactly what we are handed" contract).
 *
 * fmt = FBVIEW_FMT_15_GREY:
 *   data[w*h] of uint16_t, where data[y*w + x] is the 15-bit {cc,cc,cc} word as
 *   emitted by the DUT's ROP backend. Per-pixel on-screen value is the sole
 *   documented transform: g8 = (uint8_t)(((word & 0x1F) * 255) / 31); the three
 *   displayed channels are g8 with A = 0xFF, identical to fbview_save_png's
 *   per-pixel formula. Any other deviation between input and displayed output
 *   is a bug.
 *
 * Closing: the window-close button and the ESC key both clear an internal
 * open-flag (without destroying the texture); fbview_is_open then reports
 * FBVIEW_WINDOW_CLOSED and the host itself calls fbview_close.
 *
 * Return codes:
 *   FBVIEW_OK                       success (or "yes, still open" for
 *                                   fbview_is_open).
 *   FBVIEW_OOM                      out of display handles for fbview_open.
 *   FBVIEW_STATE_ERROR              bad args (NULL out_handle, NULL data, bad
 *                                   fmt, w<=0, h<=0) or an unknown handle.
 *   FBVIEW_WINDOW_CLOSED            fbview_is_open: the user closed the window.
 *   FBVIEW_FEATURE_UNAVAILABLE      shared lib was built WITHOUT SDL2.
 *
 * Thread safety: NOT thread-safe. The host drives all four from a single
 * thread; the display event queue is pumped inside fbview_update /
 * fbview_is_open, so no background thread is needed.
 */
fbview_rc fbview_open(int w, int h, fbview_fmt fmt, uint32_t *out_handle);

/* Blit one frame (see fbview_open for the `data` contract) and present it. */
fbview_rc fbview_update(uint32_t handle, const uint16_t *data);

/* Report whether the window for `handle` is still open (see the close/
 * FBVIEW_WINDOW_CLOSED contract in the fbview_open comment). */
fbview_rc fbview_is_open(uint32_t handle);

/* Tear down the window/renderer/texture triple for `handle`. */
fbview_rc fbview_close(uint32_t handle);

#ifdef __cplusplus
}
#endif

#endif
