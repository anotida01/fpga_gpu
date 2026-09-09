/*
 * gui_driver.c — live-GUI acceptance helper for the fbview display symbols.
 *
 * Opens one fixed-size window via fbview_open(), then in a loop (cycling the
 * given .raw framebuffer files forever) reads the next file, blits it with
 * fbview_update(), pauses, and polls fbview_is_open(). When is_open reports
 * the window is closed (ESC or the window-close button), the loop ends,
 * fbview_close() is called, and the driver exits 0.
 *
 * A .raw file is exactly w*h uint16_t (little-endian) words, row-major, in
 * the DUT's 15-bit {cc,cc,cc} layout — the same words the UVM scoreboard
 * readbacks.
 *
 * If this fbview build has no SDL2 backend, fbview_open() returns
 * FBVIEW_FEATURE_UNAVAILABLE (0x7002); the driver prints a clear message and
 * exits 1 (the symbols are still linked — the ABI is stable either way).
 */
#include "fbview.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>

#define MAX_FILES 256

int main(int argc, char **argv)
{
    int w = 320, h = 240, fps = 15;
    const char *files[MAX_FILES];
    int nfiles = 0;

    /* ---- arg parse: files positional; --w/--h/--fps options -------------- */
    for (int i = 1; i < argc; i++) {
        if (strcmp(argv[i], "--w") == 0)       { if (i + 1 < argc) w   = atoi(argv[++i]); }
        else if (strcmp(argv[i], "--h") == 0)  { if (i + 1 < argc) h   = atoi(argv[++i]); }
        else if (strcmp(argv[i], "--fps") == 0){ if (i + 1 < argc) fps = atoi(argv[++i]); }
        else if (nfiles < MAX_FILES)           files[nfiles++] = argv[i];
        else { fprintf(stderr, "gui_driver: too many .raw files (max %d)\n", MAX_FILES); return 1; }
    }
    if (nfiles < 1 || w <= 0 || h <= 0 || fps <= 0) {
        fprintf(stderr, "usage: gui_driver <raw-file-1> [raw-file-N] [--w 320 --h 240] [--fps 15]\n");
        return 1;
    }

    /* ---- open the live display ------------------------------------------- */
    uint32_t handle = 0;
    fbview_rc rc = fbview_open(w, h, FBVIEW_FMT_15_GREY, &handle);
    if (rc == FBVIEW_FEATURE_UNAVAILABLE) {
        fprintf(stderr, "fbview: SDL2 not available in this build (rc=7002)\n");
        return 1;
    }
    if (rc != FBVIEW_OK) {
        fprintf(stderr, "gui_driver: fbview_open failed (rc=%x)\n", (unsigned)rc);
        return 1;
    }
    printf("gui_driver: window %dx%d open, displaying %d file(s) at %d fps "
           "(ESC or window-close quits)\n", w, h, nfiles, fps);

    /* ---- serve frames: cycle the files until the window is closed -------- */
    uint16_t *fb = NULL;
    const size_t expect = (size_t)w * (size_t)h * sizeof(uint16_t);
    long pause_us = 1000000L / (long)fps;

    for (unsigned fi = 0; ; fi++) {
        const char *path = files[fi % (unsigned)nfiles];

        FILE *f = fopen(path, "rb");
        if (!f) { fprintf(stderr, "gui_driver: cannot open %s\n", path); break; }
        if (fb) free(fb);
        fb = (uint16_t *)malloc(expect);
        if (!fb) { fprintf(stderr, "gui_driver: malloc failed\n"); fclose(f); break; }
        size_t n = fread(fb, 1, expect, f);
        fclose(f);
        if (n != expect) {
            fprintf(stderr, "gui_driver: %s: expected %zu bytes of 16-bit words, got %zu\n",
                    path, expect, n);
            break;
        }

        rc = fbview_update(handle, fb);
        if (rc != FBVIEW_OK)
            break;   /* window closed (or an error) — fall through to clean exit */

        struct timespec ts = { pause_us / 1000000L, (pause_us % 1000000L) * 1000L };
        nanosleep(&ts, NULL);

        rc = fbview_is_open(handle);
        if (rc != FBVIEW_OK)
            break;   /* FBVIEW_WINDOW_CLOSED: the user quit */
    }

    if (fb) free(fb);
    fbview_close(handle);
    printf("gui_driver: closed, exiting 0\n");
    return 0;
}
