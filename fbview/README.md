# fbview — framebuffer viewer (C-ABI shared library)

`fbview` is a small first-class C library that owns one job: **given a raw
framebuffer buffer in one of a known number of formats, show it** — either as
a viewable PNG file or as a live SDL2 window. It is a *viewer*, not a
renderer — it renders **exactly** the word it is handed. The only transform it
applies, on every output path, is the documented 5-bit→8-bit rescale
`cc * 255 / 31`, identical to `cmodel_golden`'s `cmodel_save_image` and to
`render_gui.py --save`.

It exports five C symbols over two features; each feature is behind an
**optional** build dependency, and the public ABI is identical in every build
combo (see the matrix below):

- **PNG save** (libpng, optional): `fbview_save_png`
- **Live display** (SDL2, optional): `fbview_open` / `fbview_update` /
  `fbview_is_open` / `fbview_close` — fixed-size window, streaming blit,
  ESC/window-close detection, no background thread

It does no mesh loading, no rendering, and no DPI-C import (the sim-side
consumer is a separate package).

## Public C-ABI — `include/fbview.h`

```c
/* PNG save (libpng-optional) */
fbview_rc fbview_save_png(const char *path, int w, int h,
                          const uint16_t *data, fbview_fmt fmt);

/* Live display (SDL2-optional); the host owns timing and close-detection */
fbview_rc fbview_open(int w, int h, fbview_fmt fmt, uint32_t *out_handle);
fbview_rc fbview_update(uint32_t handle, const uint16_t *data);
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
| `FBVIEW_FEATURE_UNAVAILABLE` | `0x7002` | the affected symbol's dependency (libpng / SDL2) was absent at build time |
| `FBVIEW_WINDOW_CLOSED` | `0x7003` | live display: the user closed the window (reported by `fbview_is_open`, or `fbview_update` on a closed window) |

Input formats (`fbview_fmt`, one value today):

| Value | Meaning |
|---|---|
| `FBVIEW_FMT_15_GREY` (= `0`) | `uint16_t[w*h]`, `data[y*w+x]` is the 15-bit `{cc,cc,cc}` word (the DUT ROP layout). PNG out: 8-bit RGB, three identical channels, top-down. Display out: three identical channels, A=0xFF. |

More `FBVIEW_FMT_*` values (Q13.14 raw, 8-bit RGB, …) can be added later
without breaking this ABI — consumers already switch on `fmt` at call time.

The **display lifecycle**: `fbview_open(w, h, …, &handle)` once →
`fbview_update(handle, frame)` per frame → `fbview_is_open(handle)` each
frame (poll; the event queue is pumped inside `update`/`is_open`, so no
background thread is needed and the host stays on a single thread) →
`fbview_close(handle)` when done. ESC and the window-close button clear an
internal flag without destroying the texture; the host detects it via
`fbview_is_open` → `FBVIEW_WINDOW_CLOSED`, then closes itself. The display
window is fixed-size and not resizable (a resize would change the blit
scaling and break "render exactly what we are handed").

## Build

Both dependencies are **optional** and independently gated (mirrored C macro
`FBVIEW_HAVE_PNG` / `FBVIEW_HAVE_SDL2`, same pattern):

| libpng | SDL2 | active feature | still exported |
|---|---|---|---|
| on | on | PNG save + live display | all 5 symbols |
| on | off | PNG save | all 5 (display = returns `0x7002`) |
| off | on | live display | all 5 (`fbview_save_png` = returns `0x7002`) |
| off | off | none | all 5 (all return `0x7002`) |

Detection: CMake uses `find_package(PNG QUIET)` / `find_package(SDL2 QUIET)`;
the Makefile uses pkg-config with the same three override modes for each
dependency (`WITH_PNG`, `WITH_SDL2`: auto-detected / `=1` hard-error-if-missing /
`=0` force-stub) as for each other.

**CMake:**

```sh
cmake -S fbview -B build-cmake -DCMAKE_BUILD_TYPE=Debug
cmake --build build-cmake --target fbview            # the library
cmake --build build-cmake --target fbview_gui_driver # the live-GUI acceptance helper
```

**Make (CMake-free):**

```sh
cd fbview
make            # auto-detect libpng + SDL2 via pkg-config; graceful degrade to stub
make gui_driver # build/gui_driver (links the lib via $ORIGIN rpath)
make info       # print the chosen modes: libpng | SDL2 ENABLED | STUB
```

## Host driver — `tests/gui_driver.c`

The live-display acceptance helper: opens one fixed `--w`×`--h` window and
cycles a stream of raw `.raw` framebuffer files (each exactly `w*h` uint16
words, little-endian) forever at `--fps` (default 15):

```sh
build/gui_driver path/to/grad.raw --w 320 --h 240 --fps 15
# ESC or the window-close button quits cleanly (exit 0)
```

If the linked lib has no SDL2 backend, it prints
`fbview: SDL2 not available in this build (rc=7002)` and exits 1.
