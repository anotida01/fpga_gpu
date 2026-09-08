// fbview_save.cpp — v1 implementation of fbview_save_png (placeholder TU).
//
// v1: PNG save of a 15-bit {cc,cc,cc} framebuffer. libpng is optional; when
// absent the symbol is still exported and returns FBVIEW_FEATURE_UNAVAILABLE.
#include "fbview.h"

#include <stdlib.h>

#ifdef FBVIEW_HAVE_PNG
#include <png.h>
#endif

#ifdef FBVIEW_HAVE_PNG

fbview_rc fbview_save_png(const char *path, int w, int h,
                          const uint16_t *data, fbview_fmt fmt) {
    (void)fmt;
    // Minimal placeholder: write valid arg check, real encode lands with the
    // full implementation.
    if (!path || !path[0] || !data || w <= 0 || h <= 0)
        return FBVIEW_STATE_ERROR;
    return FBVIEW_FILE_ERROR;
}

#else  /* !FBVIEW_HAVE_PNG — feature compiled out */

fbview_rc fbview_save_png(const char *path, int w, int h,
                          const uint16_t *data, fbview_fmt fmt) {
    (void)path; (void)w; (void)h; (void)data; (void)fmt;
    return FBVIEW_FEATURE_UNAVAILABLE;
}

#endif  /* FBVIEW_HAVE_PNG */
