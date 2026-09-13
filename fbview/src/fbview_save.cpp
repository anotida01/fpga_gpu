// fbview_save.cpp — C-ABI implementation of fbview_save_png (v1).
//
// Serializes a raw framebuffer buffer in a known format to a viewable PNG. v1
// accepts exactly one input format, FBVIEW_FMT_15_GREY (a uint16_t[w*h] of
// 15-bit {cc,cc,cc} words). fbview is a viewer: it renders EXACTLY the word it
// is handed, applying only the documented 5-bit->8-bit rescale (cc*255/31). No
// mesh loading, no rendering, no DPI-C import, no event loop in this TU.
//
// libpng is OPTIONAL (see CMakeLists.txt / Makefile): when present, the
// FBVIEW_HAVE_PNG branch below is compiled; when absent, the #else stub is
// compiled instead and fbview_save_png still exists in the .so (returns
// FBVIEW_FEATURE_UNAVAILABLE), keeping the ABI stable across builds. In either
// case the symbol is exported (nm -D shows T).

#include "fbview.h"

#include <stdio.h>
#include <stdlib.h>
#include <stdint.h>

#ifdef FBVIEW_HAVE_PNG
#include <png.h>
#endif

#ifdef FBVIEW_HAVE_PNG

fbview_rc fbview_save_png(const char *path, int w, int h,
                          const uint16_t *data, fbview_fmt fmt) {
    if (!path || !path[0])                 return FBVIEW_STATE_ERROR;
    if (!data)                             return FBVIEW_STATE_ERROR;
    if (w <= 0 || h <= 0)                  return FBVIEW_STATE_ERROR;
    if (fmt != FBVIEW_FMT_15_GREY)         return FBVIEW_STATE_ERROR;

    size_t row_bytes = (size_t)w * (size_t)h * (size_t)3;
    unsigned char *row = (unsigned char*)malloc(row_bytes);
    if (!row)                              return FBVIEW_OOM;

    for (int y = 0; y < h; y++) {
        unsigned char *dst = row + (size_t)y * (size_t)w * (size_t)3;
        const uint16_t *src = data + (size_t)y * (size_t)w;
        for (int x = 0; x < w; x++) {
            // Per-pixel output formula. The only transform the tool applies, and
            // it must stay bit-identical to the C-model PNG writer and to
            // render_gui.py's --save byte formula. We read the lowest 5-bit
            // channel (& 0x1F): bits [4:0] hold the 5-bit grey intensity L in both
            // the legacy {cc,cc,cc} pack and the RGB565 grey pack {L, {L, L[4]}, L}.
            // If the word is NOT grey, the tool still produces a well-defined output
            // (the Blue channel); it does NOT attempt to detect or "fix" a non-grey word.
            int32_t cc = (int32_t)(src[x] & 0x1F);
            uint8_t g8 = (uint8_t)((cc * 255) / 31);
            dst[x * 3 + 0] = g8;
            dst[x * 3 + 1] = g8;
            dst[x * 3 + 2] = g8;
        }
    }

    FILE *fp = fopen(path, "wb");
    if (!fp) { free(row); return FBVIEW_FILE_ERROR; }

    png_structp png = png_create_write_struct(PNG_LIBPNG_VER_STRING, NULL, NULL, NULL);
    if (!png) { fclose(fp); free(row); return FBVIEW_FILE_ERROR; }
    png_infop info = png_create_info_struct(png);
    if (!info) {
        png_destroy_write_struct(&png, NULL);
        fclose(fp); free(row);
        return FBVIEW_FILE_ERROR;
    }
    if (setjmp(png_jmpbuf(png))) {
        png_destroy_write_struct(&png, &info);
        fclose(fp); free(row);
        return FBVIEW_FILE_ERROR;
    }

    png_init_io(png, fp);
    png_set_IHDR(png, info,
                 w, h,
                 8,                       /* bit depth */
                 PNG_COLOR_TYPE_RGB,      /* 3 channels, identical */
                 PNG_INTERLACE_NONE,
                 PNG_COMPRESSION_TYPE_DEFAULT,
                 PNG_FILTER_TYPE_DEFAULT);
    png_write_info(png, info);

    /* Write the buffer row by row in top-down order. */
    for (int y = 0; y < h; y++)
        png_write_row(png, row + (size_t)y * (size_t)w * (size_t)3);

    png_write_end(png, info);
    png_destroy_write_struct(&png, &info);
    int rc = fclose(fp);
    free(row);
    return (rc == 0) ? FBVIEW_OK : FBVIEW_FILE_ERROR;
}

#else  /* !FBVIEW_HAVE_PNG — feature compiled out */

fbview_rc fbview_save_png(const char *path, int w, int h,
                          const uint16_t *data, fbview_fmt fmt) {
    (void)path; (void)w; (void)h; (void)data; (void)fmt;
    return FBVIEW_FEATURE_UNAVAILABLE;
}

#endif  /* FBVIEW_HAVE_PNG */
