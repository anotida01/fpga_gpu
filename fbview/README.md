# fbview — framebuffer → PNG viewer (C-ABI shared library)

`fbview` is a small first-class C library that owns one job: **given a raw
framebuffer buffer in one of a known number of formats, emit a viewable PNG.**
It is a *viewer*, not a renderer — it renders **exactly** the word it is
handed. The only transform it applies is the documented 5-bit→8-bit rescale
`cc * 255 / 31`, identical to `cmodel_golden`'s `cmodel_save_image` and to
`render_gui.py --save`.

v1 (this work order) exports **one** symbol, `fbview_save_png`, and accepts
**one** input format, 15-bit `{cc,cc,cc}` grey words in a `uint16_t[w*h]`
array — the exact layout the DUT's ROP backend emits and the UVM scoreboard
reads back. It does no mesh loading, rendering, DPI-C import, or event loop.

The **live-GUI** half (`fbview_open` / `fbview_update` / `fbview_close` /
`fbview_is_open`, SDL2-gated) is a separate work order that extends the same
`fbview.h` header and the same build files.

## Public C-ABI (v1) — `include/fbview.h`

One symbol:

```c
fbview_rc fbview_save_png(const char *path, int w, int h,
                          const uint16_t *data, fbview_fmt fmt);
```

Return codes (`fbview_rc` = `unsigned int`):

| Code | Value | Meaning |
|---|---|---|
| `FBVIEW_OK` | `0` | written successfully |
| `FBVIEW_OOM` | `1` | allocation failure on the intermediate byte buffer |
| `FBVIEW_FILE_ERROR` | `2` | `fopen` / libpng write failure |
| `FBVIEW_STATE_ERROR` | `3` | bad args (NULL/empty path, NULL data, `w<=0`, `h<=0`) |
| `FBVIEW_FEATURE_UNAVAILABLE` | `0x7002` | the shared lib was built **without** libpng |

Input formats (`fbview_fmt`):

| Value | Meaning |
|---|---|
| `FBVIEW_FMT_15_GREY` (= `0`) | `uint16_t[w*h]`, `data[y*w+x]` is the 15-bit `{cc,cc,cc}` word. Output is 8-bit RGB (colortype 2), three identical channels, top-down row-major. |

More `FBVIEW_FMT_*` values (Q13.14 raw, 8-bit RGB, …) can be added later
without breaking this ABI — consumers already switch on `fmt` at call time.

## Build

`libpng` is **optional** in both flows: when present the `fbview_save_png`
implementation is active; when absent the build stays green and the symbol is
still exported (it returns `FBVIEW_FEATURE_UNAVAILABLE`).

**CMake:**

```sh
cmake -S fbview -B build-cmake -DCMAKE_BUILD_TYPE=Debug
cmake --build build-cmake --target fbview
```

**Make (CMake-free):**

```sh
cd fbview
make            # auto-detect libpng via pkg-config; graceful degrade to stub
make info       # print the chosen mode: libpng ENABLED | STUB
```

Override modes: `WITH_PNG=1 make` (hard error if libpng is missing),
`WITH_PNG=0 make` (force the PNG-less stub).
