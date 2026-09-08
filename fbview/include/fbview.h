/*
 * fbview.h — public C-ABI for the fbview shared library (v1).
 *
 * v1 exports exactly one symbol, fbview_save_png. The live-GUI symbols are a
 * separate work order and are not part of this header yet.
 */
#ifndef FBVIEW_H
#define FBVIEW_H

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef unsigned int fbview_rc;   /* return codes (0 == OK) */

enum {
    FBVIEW_OK                     = 0,
    FBVIEW_OOM                    = 1,
    FBVIEW_FILE_ERROR             = 2,
    FBVIEW_STATE_ERROR            = 3,
    FBVIEW_FEATURE_UNAVAILABLE    = 0x7002
};

typedef enum { FBVIEW_FMT_15_GREY = 0 } fbview_fmt;

fbview_rc fbview_save_png(const char *path, int w, int h,
                          const uint16_t *data, fbview_fmt fmt);

#ifdef __cplusplus
}
#endif

#endif
