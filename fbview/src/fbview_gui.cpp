/*
 * fbview_gui.cpp — live-GUI display symbols for the fbview shared library.
 *
 * Implements fbview_open / fbview_update / fbview_is_open / fbview_close /
 * fbview_put_pixel (see include/fbview.h for the contract, the documented
 * per-pixel transform, and the close/ESC semantics) on top of SDL2.
 *
 * Build modes:
 *   -FBVIEW_HAVE_SDL2  real SDL2 backend (window + renderer + streaming texture).
 *   default            stub: all five symbols still exported, each call returns
 *                       FBVIEW_FEATURE_UNAVAILABLE (ABI is identical either way).
 *
 * SDL lifecycle (implementation detail, not ABI): the first fbview_open()
 * initializes SDL video (SDL_Init(SDL_INIT_VIDEO)) and the last fbview_close()
 * that empties the handle pool calls SDL_Quit(). The host driver therefore
 * never touches SDL directly.
 *
 * Thread safety: NOT thread-safe (single host thread drives all four symbols).
 */
extern "C" {
#include "fbview.h"
}

#ifdef FBVIEW_HAVE_SDL2

#include <SDL.h>
#include <stdio.h>

/* --- Internal state ------------------------------------------------------- */

/* One live display = window + renderer + streaming ARGB8888 texture triple.
 * Handles are 1-based indices into this fixed pool (0 = invalid sentinel);
 * at most FBVIEW_MAX_DISPLAYS windows can be open simultaneously. */
#define FBVIEW_MAX_DISPLAYS 8

struct fbview_gstate {
    SDL_Window  *win;
    SDL_Renderer *ren;
    SDL_Texture *tex;
    int w, h;
    int open_flag;   /* 1 = window still open, 0 = never opened / closed */
};

static fbview_gstate g_state[FBVIEW_MAX_DISPLAYS];
static int           g_sdl_initialized = 0;

/* Pump the SDL event queue for this display; clear open_flag (without
 * destroying GPU resources) when the user closed the window or pressed ESC. */
static void fbview_pump_closed(fbview_gstate *gs)
{
    if (!gs->open_flag)
        return;
    SDL_PumpEvents();
    SDL_Event ev;
    while (SDL_PollEvent(&ev)) {
        if (ev.type == SDL_QUIT)
            gs->open_flag = 0;
        else if (ev.type == SDL_KEYDOWN && ev.key.keysym.sym == SDLK_ESCAPE)
            gs->open_flag = 0;
    }
}

/* Release a pool slot (destroying SDL objects if they were live). */
static void fbview_release_slot(fbview_gstate *gs)
{
    if (gs->tex)  { SDL_DestroyTexture(gs->tex);   gs->tex = NULL; }
    if (gs->ren)  { SDL_DestroyRenderer(gs->ren);  gs->ren = NULL;  }
    if (gs->win)  { SDL_DestroyWindow(gs->win);    gs->win = NULL;  }
    gs->w = gs->h = 0;
    gs->open_flag = 0;
}

/* -------------------------------------------------------------------------- */

fbview_rc fbview_open(int w, int h, fbview_fmt fmt, uint32_t *out_handle)
{
    if (!out_handle || w <= 0 || h <= 0 || fmt != FBVIEW_FMT_15_GREY)
        return FBVIEW_STATE_ERROR;

    if (!g_sdl_initialized) {
        if (SDL_Init(SDL_INIT_VIDEO) != 0) {
            fprintf(stderr, "fbview: SDL_Init(video) failed: %s\n", SDL_GetError());
            return FBVIEW_STATE_ERROR;
        }
        g_sdl_initialized = 1;
    }

    /* Allocate a free pool slot (1-based). */
    fbview_gstate *gs = NULL;
    for (unsigned i = 1; i <= FBVIEW_MAX_DISPLAYS; i++)
        if (g_state[i-1].open_flag == 0 && g_state[i-1].win == NULL) {
            gs = &g_state[i-1];
            break;
        }
    if (!gs) {
        fprintf(stderr, "fbview: no free display handles (%u)\n",
                (unsigned)FBVIEW_MAX_DISPLAYS);
        return FBVIEW_OOM;
    }

    char title[64];
    snprintf(title, sizeof title, "fbview %dx%d", w, h);

    gs->win = SDL_CreateWindow(title, SDL_WINDOWPOS_CENTERED, SDL_WINDOWPOS_CENTERED,
                               w, h, SDL_WINDOW_SHOWN /* NOT resizable: fixed blit scale */);
    if (!gs->win) {
        fprintf(stderr, "fbview: SDL_CreateWindow failed: %s\n", SDL_GetError());
        return FBVIEW_STATE_ERROR;
    }

    gs->ren = SDL_CreateRenderer(gs->win, -1, SDL_RENDERER_ACCELERATED);
    if (!gs->ren)
        gs->ren = SDL_CreateRenderer(gs->win, -1, SDL_RENDERER_SOFTWARE);
    if (!gs->ren) {
        fprintf(stderr, "fbview: SDL_CreateRenderer failed: %s\n", SDL_GetError());
        fbview_release_slot(gs);
        return FBVIEW_STATE_ERROR;
    }

    gs->tex = SDL_CreateTexture(gs->ren, SDL_PIXELFORMAT_ARGB8888,
                                SDL_TEXTUREACCESS_STREAMING, w, h);
    if (!gs->tex) {
        fprintf(stderr, "fbview: SDL_CreateTexture failed: %s\n", SDL_GetError());
        fbview_release_slot(gs);
        return FBVIEW_STATE_ERROR;
    }

    gs->w = w;
    gs->h = h;
    gs->open_flag = 1;
    *out_handle = (uint32_t)(gs - g_state) + 1U;
    return FBVIEW_OK;
}

fbview_rc fbview_update(uint32_t handle, const uint16_t *data)
{
    if (handle < 1 || handle > FBVIEW_MAX_DISPLAYS)
        return FBVIEW_STATE_ERROR;
    fbview_gstate *gs = &g_state[handle-1];
    if (!gs->open_flag)
        return FBVIEW_WINDOW_CLOSED;   /* user closed it; host will fbview_close */
    if (!data)
        return FBVIEW_STATE_ERROR;

    void *px;
    int pitch = 0;
    if (SDL_LockTexture(gs->tex, NULL, &px, &pitch) != 0) {
        fprintf(stderr, "fbview: SDL_LockTexture failed: %s\n", SDL_GetError());
        return FBVIEW_STATE_ERROR;
    }

    /* Sole documented transform — identical to the PNG path: cc*255/31.
     * ARGB8888 in memory (little-endian) = byte order R G B A. */
    const int n = gs->w * gs->h;
    for (int i = 0; i < n; i++) {
        const uint8_t g = (uint8_t)(((data[i] & 0x1F) * 255u) / 31u);
        uint8_t *dst = (uint8_t *)px + (size_t)(i / gs->w) * (size_t)pitch + (size_t)(i % gs->w) * 4u;
        dst[0] = g;
        dst[1] = g;
        dst[2] = g;
        dst[3] = 0xFF;
    }
    SDL_UnlockTexture(gs->tex);

    SDL_RenderClear(gs->ren);
    SDL_RenderCopy(gs->ren, gs->tex, NULL, NULL);
    SDL_RenderPresent(gs->ren);

    fbview_pump_closed(gs);
    return FBVIEW_OK;
}

/* Per-pixel blit (the sim-driven live-push entry point; see the header for the
 * full contract). One 1x1 render fill + present; paced by the caller (the DUT's
 * own raster rate when driven from the sim). */
fbview_rc fbview_put_pixel(uint32_t handle, int x, int y, uint32_t word)
{
    if (handle < 1 || handle > FBVIEW_MAX_DISPLAYS)
        return FBVIEW_STATE_ERROR;
    fbview_gstate *gs = &g_state[handle-1];
    fbview_pump_closed(gs);
    if (!gs->open_flag)
        return FBVIEW_WINDOW_CLOSED;   /* user closed it; caller stops pushing */
    if (x < 0 || x >= gs->w || y < 0 || y >= gs->h)
        return FBVIEW_STATE_ERROR;

    /* Sole documented transform — same formula as fbview_update / fbview_save_png:
     * cc = (word & 0x1F) on the DUT's full word, g8 = cc*255/31. */
    const uint8_t g = (uint8_t)(((word & 0x1Fu) * 255u) / 31u);

    SDL_SetRenderDrawColor(gs->ren, g, g, g, 0xFF);
    SDL_Rect r = { x, y, 1, 1 };
    if (SDL_RenderFillRect(gs->ren, &r) != 0) {
        fprintf(stderr, "fbview: SDL_RenderFillRect failed: %s\n", SDL_GetError());
        return FBVIEW_STATE_ERROR;
    }
    SDL_RenderPresent(gs->ren);
    return FBVIEW_OK;
}

fbview_rc fbview_is_open(uint32_t handle)
{
    if (handle < 1 || handle > FBVIEW_MAX_DISPLAYS)
        return FBVIEW_STATE_ERROR;
    fbview_gstate *gs = &g_state[handle-1];
    fbview_pump_closed(gs);
    return gs->open_flag ? FBVIEW_OK : FBVIEW_WINDOW_CLOSED;
}

fbview_rc fbview_close(uint32_t handle)
{
    if (handle < 1 || handle > FBVIEW_MAX_DISPLAYS)
        return FBVIEW_STATE_ERROR;
    fbview_gstate *gs = &g_state[handle-1];
    fbview_release_slot(gs);

    /* If the pool is now empty, release the shared SDL video subsystem. */
    if (g_sdl_initialized) {
        int any = 0;
        for (unsigned i = 0; i < FBVIEW_MAX_DISPLAYS; i++)
            if (g_state[i].open_flag) { any = 1; break; }
        if (!any) {
            SDL_Quit();
            g_sdl_initialized = 0;
        }
    }
    return FBVIEW_OK;
}

#else  /* !FBVIEW_HAVE_SDL2 — ABI-stable stub (lib built without SDL2) */

/* Same five symbols, all reporting the feature is unavailable in this build. */

fbview_rc fbview_open(int w, int h, fbview_fmt fmt, uint32_t *out_handle)
{
    (void)w; (void)h; (void)fmt; (void)out_handle;
    return FBVIEW_FEATURE_UNAVAILABLE;
}

fbview_rc fbview_update(uint32_t handle, const uint16_t *data)
{
    (void)handle; (void)data;
    return FBVIEW_FEATURE_UNAVAILABLE;
}

fbview_rc fbview_is_open(uint32_t handle)
{
    (void)handle;
    return FBVIEW_FEATURE_UNAVAILABLE;
}

fbview_rc fbview_close(uint32_t handle)
{
    (void)handle;
    return FBVIEW_FEATURE_UNAVAILABLE;
}

fbview_rc fbview_put_pixel(uint32_t handle, int x, int y, uint32_t word)
{
    (void)handle; (void)x; (void)y; (void)word;
    return FBVIEW_FEATURE_UNAVAILABLE;
}

#endif  /* FBVIEW_HAVE_SDL2 */
