# fbview — framebuffer viewer (C-ABI shared library)

`fbview` is a small first-class C library that owns one job: **given a raw
framebuffer buffer in one of a known number of formats, show it** — either as
a viewable PNG file or as a live window (an **SDL2** or **SDL1** backend, or
neither — a graceful stub). It is a *viewer*, not a
renderer — it renders **exactly** the word it is handed. The only transform it
applies, on every output path, is the documented 5-bit→8-bit rescale
`cc * 255 / 31`, identical to `cmodel_golden`'s `cmodel_save_image` and to
`render_gui.py --save`.

It exports six C symbols over two features; each feature is behind an
**optional** build dependency, and the public ABI is identical in every build
combo (see the matrix below):

- **PNG save** (libpng, optional): `fbview_save_png`
- **Live display** (SDL2 **or** SDL1, optional; exactly one backend per build):
  `fbview_open` / `fbview_update` /
  `fbview_put_pixel` / `fbview_is_open` / `fbview_close` — fixed-size
  window, streaming blit (whole-frame **and** per-pixel),
  ESC/window-close detection, no background thread

It does no mesh loading, no rendering, and no DPI-C import (the sim-side
consumer is a separate package).

## Public C-ABI — `include/fbview.h`

```c
/* PNG save (libpng-optional) */
fbview_rc fbview_save_png(const char *path, int w, int h,
                          const uint16_t *data, fbview_fmt fmt);

/* Live display (SDL2-/SDL1-optional; the host owns timing and close-detection) */
fbview_rc fbview_open(int w, int h, fbview_fmt fmt, uint32_t *out_handle);
fbview_rc fbview_update(uint32_t handle, const uint16_t *data);   /* whole frame */
fbview_rc fbview_put_pixel(uint32_t handle, int x, int y, uint32_t word); /* one pixel (DPI-C basic-friendly) */
fbview_rc fbview_is_open(uint32_t handle);
fbview_rc fbview_close(uint32_t handle);
```

`fbview_rc` is `unsigned int`. Return codes:

| Code | Value | Meaning |
|---|---|---|
| `FBVIEW_OK` | `0` | success (or "still open" for `fbview_is_open`) |
| `FBVIEW_OOM` | `1` | allocation failure (PNG row buffer / no free display handle) |
| `FBVIEW_FILE_ERROR` | `2` | `fopen` / libpng write failure |
| `FBVIEW_STATE_ERROR` | `3` | bad args (NULLs, `w<=0`/`h<=0`, bad `fmt`, unknown handle) or resource-creation failure |
| `FBVIEW_FEATURE_UNAVAILABLE` | `0x7002` | the affected symbol's dependency (libpng / a display backend) was absent at build time |
| `FBVIEW_WINDOW_CLOSED` | `0x7003` | live display: the user closed the window (reported by `fbview_is_open`, or `fbview_update` / `fbview_put_pixel` on a closed window) |

Input formats (`fbview_fmt`, one value today):

| Value | Meaning |
|---|---|
| `FBVIEW_FMT_15_GREY` (= `0`) | `uint16_t[w*h]`, `data[y*w+x]` is the 15-bit `{cc,cc,cc}` word (the DUT ROP layout). PNG out: 8-bit RGB, three identical channels, top-down. Display out: three identical channels, A=0xFF. |

More `FBVIEW_FMT_*` values (Q13.14 raw, 8-bit RGB, …) can be added later
without breaking this ABI — consumers already switch on `fmt` at call time.

The **display lifecycle**: `fbview_open(w, h, …, &handle)` once →
`fbview_update(handle, frame)` per frame (whole frame), **or**
`fbview_put_pixel(h, x, y, word)` per drawn pixel (the per-pixel entry point
for a sim-driven live push: `word` is the DUT's full 32-bit framebuffer word,
the C side takes `cc = word & 0x1F` and applies the same single documented
transform) → `fbview_is_open(handle)` / check the `put_pixel` return each step
(poll; the event queue is pumped inside `update`/`put_pixel`/`is_open`, so no
background thread is needed and the host stays on a single thread) →
`fbview_close(handle)` when done. ESC and the window-close button clear an
internal flag without destroying the texture; the host detects it via
`fbview_is_open` → `FBVIEW_WINDOW_CLOSED`, then closes itself. The display
window is fixed-size and not resizable (a resize would change the blit
scaling and break "render exactly what we are handed").

## Build

Both dependencies are **optional**: libpng is independently gated, and the
display half has exactly **one** backend selected per build — **SDL2**
(preferred), **SDL1** (next), or **neither** (graceful stub). The mirrored C
macros are `FBVIEW_HAVE_PNG` and `FBVIEW_HAVE_SDL2` / `FBVIEW_HAVE_SDL1` (same
pattern); the backend is chosen by swapping the single display source unit
(`src/fbview_gui.cpp` = SDL2 **or** its `#else` stub; `src/fbview_gui_sdl1.cpp`
= SDL1) in the Makefile — only one is ever compiled in.

Six legal build combos (2 libpng × 3 display backends), all keep the full six-symbol ABI:

| libpng | display backend | active feature | `fbview_save_png` / the 5 display symbols |
|---|---|---|---|
| on | SDL2 (default) | PNG save + live display | both work |
| on | SDL1 | PNG save + live display | both work |
| on | neither | PNG save only | save_png works; display = `0x7002` |
| off | SDL2 | live display only | save_png = `0x7002`; display works |
| off | SDL1 | live display only | save_png = `0x7002`; display works |
| off | neither | none | all 6 return `0x7002` |

Detection (Makefile, pkg-config): libpng = `libpng`; display = auto-precedence
`sdl2` → `sdl` (SDL1) → no SDL. CMake (not used by the sim flow) still does
`find_package(PNG QUIET)` / `find_package(SDL2 QUIET)` and knows only the
SDL2/stub split — the SDL1 backend is Makefile-only for now (see the work
order's out-of-scope note).

Override knobs (all optional; `=1` hard-errors if the pkg is missing, `=0`
skips it):
- `WITH_PNG` = `0`/`1`/auto (libpng)
- `WITH_SDL2` = `0`/`1`/auto and `WITH_SDL1` = `0`/`1`/auto (display backend)
  - auto (default): use SDL2 if present, else SDL1 if present, else stub.
  - `WITH_SDL1=1` (and SDL1 present): force the **SDL1** backend even if SDL2
    is also present. `WITH_SDL2=1`: force SDL2. Forcing BOTH is a hard error.
  - `WITH_SDL2=0 WITH_SDL1=0`: force the pure display stub.

**CMake:**

```sh
cmake -S fbview -B build-cmake -DCMAKE_BUILD_TYPE=Debug
cmake --build build-cmake --target fbview            # the library
cmake --build build-cmake --target fbview_gui_driver # the live-GUI acceptance helper
```

**Make (CMake-free):**

```sh
cd fbview
make            # auto-detect libpng + a display backend (SDL2 -> SDL1 -> stub); graceful degrade
WITH_SDL1=1 make # force the SDL1 backend (e.g. an SDL2-less host that ships SDL1)
make gui_driver # build/gui_driver (links the lib via $ORIGIN rpath)
make info       # print the chosen modes: libpng | SDL2|SDL1 ENABLED | SDL STUB
```

## Host driver — `tests/gui_driver.c`

The live-display acceptance helper: opens one fixed `--w`×`--h` window and
cycles a stream of raw `.raw` framebuffer files (each exactly `w*h` uint16
words, little-endian) forever at `--fps` (default 15):

```sh
build/gui_driver path/to/grad.raw --w 320 --h 240 --fps 15
# ESC or the window-close button quits cleanly (exit 0)
```

If the linked lib has **no display backend** (stub build), it prints
`fbview: SDL2 not available in this build (rc=7002)` and exits 1 (message
text is cosmetic; the SDL1 backend presents identically). Otherwise it
exercises the whole-frame `fbview_update` path; the per-pixel
`fbview_put_pixel` path is consumed by the simulation-side DPI-C sink,
which is a separate package — see `tests/envs/system/gpu/`.)
