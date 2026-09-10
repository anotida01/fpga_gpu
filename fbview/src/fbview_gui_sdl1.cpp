/* fbview_gui_sdl1.cpp — SDL 1.2 display backend (the five display symbols of
 * include/fbview.h): fbview_open / fbview_update / fbview_put_pixel /
 * fbview_is_open / fbview_close.
 *
 * Compiled INSTEAD OF fbview_gui.cpp (the SDL2 backend) in an SDL1 build, as
 * selected by the Makefile's detection (SDL2 preferred, SDL1 next, stub last).
 * The public ABI is IDENTICAL to the SDL2 backend: same signatures, same
 * return codes, same sole documented transform (g8 = (word & 0x1F) * 255 / 31,
 * three identical channels, A opaque), same close semantics (ESC or the window
 * close button marks the display closed; fbview_is_open then reports
 * FBVIEW_WINDOW_CLOSED; fbview_update / fbview_put_pixel on a closed display
 * report FBVIEW_WINDOW_CLOSED).
 *
 * SDL1 differs from SDL2 in two ways this file works around:
 *   1. SDL1 is single-display per process (one video mode for the whole
 *      program). The first fbview_open therefore OWNS the display, and a
 *      second concurrent fbview_open fails with FBVIEW_OOM (no free display)
 *      — the same failure family the SDL2 backend uses for a full handle pool.
 *   2. SDL1 has no resizable-window concept and no "current surface" getter;
 *      SDL_SetVideoMode(w,h,32,0) gives a fixed-size screen whose pointer we
 *      capture at open and keep in g_screen. Present = blit our offscreen
 *      SDL_SWSURFACE backbuffer over the screen + SDL_Flip.
 *
 * Per-pixel present cost (one blit + flip) is well within the sim-driven push
 * rate (a few kHz at most). Pacing is the caller's job; this file adds no
 * delays and no threads.
 */

#include <SDL/SDL.h>                 /* SDL 1.2 headers (SDL/ directory layout) */
#include <fbview.h>

#include <cstdint>
#include <cstdio>
#include <cstddef>
#include <cstring>

namespace {

/* Mirror of the SDL2 backend's fixed pool: handles are 1-based indices into
 * this array (0 = invalid sentinel for handle values below 1 or above this).
 * The display-ownership cap (below) means at most one slot is live on SDL1. */
#define FBVIEW_MAX_DISPLAYS 8

struct fbview_s1state {
    int          w, h;
    int          open_flag; /* 1 = live, 0 = never opened / closed */
};

static fbview_s1state g_state[FBVIEW_MAX_DISPLAYS];
static int            g_sdl_initialized = 0;
static int            g_display_owner = 0;  /* slot index+1 owning the display (0 = none) */
static SDL_Surface   *g_screen = NULL;      /* process's screen surface (set at open) */
static SDL_Surface   *g_back   = NULL;      /* process's offscreen backbuffer (set at open) */

/* Pump the SDL event queue; clear open_flag (keeping the SDL surfaces so
 * fbview_close can still free the backbuffer) when the user closed the window
 * (X WM_DELETE_WINDOW -> SDL_QUIT) or pressed ESC — same contract as the SDL2
 * backend. */
static void s1_pump_closed()
{
    if (g_display_owner == 0)
        return;
    fbview_s1state *gs = &g_state[g_display_owner - 1];
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

static bool s1_has_live_slot()
{
    for (unsigned i = 0; i < FBVIEW_MAX_DISPLAYS; i++)
        if (g_state[i].open_flag)
            return true;
    return false;
}

/* Free this process's SDL surfaces (called from fbview_close). */
static void s1_release_surfaces()
{
    if (g_back)   { SDL_FreeSurface(g_back);   g_back   = NULL; }
    /* g_screen is owned by SDL1 itself; SDL_Quit() drops it. */
    g_screen = NULL;
}

/*---------------------------------------------------------------------------*/

}  // namespace

fbview_rc fbview_open(int w, int h, fbview_fmt fmt, uint32_t *out_handle)
{
    if (!out_handle || w <= 0 || h <= 0 || fmt != FBVIEW_FMT_15_GREY)
        return FBVIEW_STATE_ERROR;

    if (g_display_owner != 0)
        return FBVIEW_OOM;   /* SDL1 is single-display: another handle owns it */

    if (!g_sdl_initialized) {
        if (SDL_Init(SDL_INIT_VIDEO) != 0) {
            fprintf(stderr, "fbview: SDL_Init(video) failed: %s\n", SDL_GetError());
            return FBVIEW_STATE_ERROR;
        }
        g_sdl_initialized = 1;
    }

    /* Allocate a free pool slot (1-based). */
    fbview_s1state *gs = NULL;
    for (unsigned i = 1; i <= FBVIEW_MAX_DISPLAYS; i++)
        if (g_state[i-1].open_flag == 0) {
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

    /* SDL1: one fixed-size screen surface for the whole process. */
    g_screen = SDL_SetVideoMode(w, h, 32, 0);
    if (!g_screen) {
        fprintf(stderr, "fbview: SDL_SetVideoMode(%dx%d) failed: %s\n",
                w, h, SDL_GetError());
        return FBVIEW_STATE_ERROR;
    }
    SDL_WM_SetCaption(title, title);

    g_back = SDL_CreateRGBSurface(SDL_SWSURFACE, w, h, 32, 0, 0, 0, 0);
    if (!g_back) {
        fprintf(stderr, "fbview: SDL_CreateRGBSurface failed: %s\n", SDL_GetError());
        s1_release_surfaces();
        return FBVIEW_STATE_ERROR;
    }

    gs->w = w;
    gs->h = h;
    gs->open_flag = 1;
    g_display_owner = (int)(gs - g_state) + 1;
    *out_handle = (uint32_t)(gs - g_state) + 1U;
    return FBVIEW_OK;
}

fbview_rc fbview_update(uint32_t handle, const uint16_t *data)
{
    if (handle < 1 || handle > FBVIEW_MAX_DISPLAYS)
        return FBVIEW_STATE_ERROR;
    fbview_s1state *gs = &g_state[handle-1];
    if (!gs->open_flag)
        return FBVIEW_WINDOW_CLOSED;   /* user closed it; host will fbview_close */
    if (!data)
        return FBVIEW_STATE_ERROR;
    if (!g_back || !g_screen)
        return FBVIEW_STATE_ERROR;

    /* Sole documented transform — identical to the PNG path and to the SDL2
     * backend's fbview_update: g8 = (word & 0x1F) * 255 / 31, three identical
     * channels, A opaque. Written with the backbuffer's OWN format masks. */
    const int n = gs->w * gs->h;
    const SDL_PixelFormat *pf = g_back->format;
    const size_t rowpitch = (size_t)g_back->pitch / 4u;   /* 32bpp -> bytes/4 */
    for (int i = 0; i < n; i++) {
        const Uint32 v = (Uint32)(((data[i] & 0x1Fu) * 255u) / 31u);
        const Uint32 px = ((v << (pf->Rshift)) & pf->Rmask)
                        | ((v << (pf->Gshift)) & pf->Gmask)
                        | ((v << (pf->Bshift)) & pf->Bmask)
                        | ((0xFFu << (pf->Ashift)) & pf->Amask);
        ((Uint32 *)g_back->pixels)[(size_t)(i / gs->w) * rowpitch + (size_t)(i % gs->w)] = px;
    }

    /* Present: blit the backbuffer over the screen, then flip (vsync). */
    SDL_BlitSurface(g_back, NULL, g_screen, NULL);
    SDL_Flip(g_screen);

    s1_pump_closed();
    return FBVIEW_OK;
}

/* Per-pixel blit (the sim-driven live-push entry point; see the header for the
 * full contract). One format-mask pixel write + full blit + flip; paced by the
 * caller (the DUT's own raster rate when driven from the sim). */
fbview_rc fbview_put_pixel(uint32_t handle, int x, int y, uint32_t word)
{
    if (handle < 1 || handle > FBVIEW_MAX_DISPLAYS)
        return FBVIEW_STATE_ERROR;
    fbview_s1state *gs = &g_state[handle-1];
    s1_pump_closed();
    if (!gs->open_flag)
        return FBVIEW_WINDOW_CLOSED;   /* user closed it; caller stops pushing */
    if (x < 0 || x >= gs->w || y < 0 || y >= gs->h)
        return FBVIEW_STATE_ERROR;
    if (!g_back || !g_screen)
        return FBVIEW_STATE_ERROR;

    /* Sole documented transform — same formula as fbview_update / the PNG path
     * / the SDL2 backend: cc = (word & 0x1F), g8 = cc * 255 / 31. */
    const Uint32 v = (Uint32)(((word & 0x1Fu) * 255u) / 31u);
    const SDL_PixelFormat *pf = g_back->format;
    const Uint32 px = ((v << (pf->Rshift)) & pf->Rmask)
                    | ((v << (pf->Gshift)) & pf->Gmask)
                    | ((v << (pf->Bshift)) & pf->Bmask)
                    | ((0xFFu << (pf->Ashift)) & pf->Amask);
    ((Uint32 *)g_back->pixels)[(size_t)y * ((size_t)g_back->pitch / 4u) + (size_t)x] = px;

    SDL_BlitSurface(g_back, NULL, g_screen, NULL);
    SDL_Flip(g_screen);
    return FBVIEW_OK;
}

fbview_rc fbview_is_open(uint32_t handle)
{
    if (handle < 1 || handle > FBVIEW_MAX_DISPLAYS)
        return FBVIEW_STATE_ERROR;
    fbview_s1state *gs = &g_state[handle-1];
    s1_pump_closed();
    return gs->open_flag ? FBVIEW_OK : FBVIEW_WINDOW_CLOSED;
}

fbview_rc fbview_close(uint32_t handle)
{
    if (handle < 1 || handle > FBVIEW_MAX_DISPLAYS)
        return FBVIEW_STATE_ERROR;
    fbview_s1state *gs = &g_state[handle-1];
    gs->open_flag = 0;
    if (g_display_owner == (int)(gs - g_state) + 1)
        g_display_owner = 0;

    s1_release_surfaces();

    /* If no slot is live now, release the shared SDL video subsystem
     * (SDL1: this also drops the screen surface). */
    if (g_sdl_initialized && !s1_has_live_slot()) {
        SDL_Quit();
        g_sdl_initialized = 0;
    }
    return FBVIEW_OK;
}
