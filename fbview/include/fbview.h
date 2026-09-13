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
 * `fmt` at call time.
 *
 * **RGB565 grey compatibility:** FBVIEW_FMT_15_GREY is bit-exactly compatible
 * with 16-bit RGB565 grey words {L, {L, L[4]}, L} (locked colour contract) for
 * the sole documented transform (word & 0x1F): bits [4:0] (Blue) hold the 5-bit
 * intensity L in BOTH the legacy 15-bit {cc,cc,cc} pack and the RGB565 pack,
 * so no separate format enum is needed for the RGB565 grey framebuffer. */
typedef enum { FBVIEW_FMT_15_GREY = 0 } fbview_fmt;

/*
 * Serialize a raw framebuffer buffer to a PNG at `path`.
 *
 *   fmt = FBVIEW_FMT_15_GREY:
 *     data[w*h] of uint16_t, where data[y*w + x] is the 15-bit {cc,cc,cc} word
 *     (bits [4:0]=R=cc, [9:5]=G=cc, [14:10]=B=cc) as emitted by the DUT's ROP
 *     backend and as read back by the UVM scoreboard.
 *     Per-pixel output formula: int32_t cc = (word & 0x1F); out = (uint8_t)(cc * 255 / 31).
 *     (Bits [4:0] are the 5-bit grey intensity in both the legacy 15-bit {cc,cc,cc}
 *     pack and the RGB565 grey pack {L, {L, L[4]}, L} — bit-identical decode.)
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
 *   FBVIEW_WINDOW_CLOSED            live display: the user closed the window
 *                                   (reported by fbview_is_open, and by
 *                                   fbview_update / fbview_put_pixel on a
 *                                   handle whose window has been closed).
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

/* Blit ONE pixel at (x, y) of the window referenced by `handle` (the window's
 * open size from fbview_open), then present and pump events — so a user close
 * (ESC / window-close button) is detected on the call that sees it. This is
 * the per-pixel entry point for the sim-driven live push (each call is the
 * moment the DUT drew that pixel; the display is paced by the raster itself,
 * no host-side delay needed).
 *
 * `word` is the DUT's FULL 32-bit framebuffer word, passed verbatim (e.g.
 * `int unsigned` from SystemVerilog). The C side takes `cc = word & 0x1F` and
 * applies the ONE documented transform, g8 = (cc * 255) / 31, into one
 * ARGB8888 pixel (R = G = B = g8, A = 0xFF) — the same single per-pixel formula
 * used by fbview_save_png and by fbview_update for FBVIEW_FMT_15_GREY.
 * No reordering, LUT, gamma or anything else.
 *
 * NOT thread-safe (same as the rest of the display half): the caller drives it
 * from ONE thread (the sim event thread, or the host).
 *
 * Return codes:
 *   FBVIEW_OK                       blited + presented.
 *   FBVIEW_STATE_ERROR              `handle` unknown, or x < 0 || x >= w || y < 0 || y >= h.
 *   FBVIEW_WINDOW_CLOSED            `handle` valid but the user closed the window.
 *   FBVIEW_FEATURE_UNAVAILABLE      this build has no SDL2 backend (identical ABI).
 */
fbview_rc fbview_put_pixel(uint32_t handle, int x, int y, uint32_t word);

#ifdef __cplusplus
}
#endif

#endif
