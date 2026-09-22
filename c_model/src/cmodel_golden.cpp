// cmodel_golden.cpp — C-ABI implementation for the cmodel_golden shared library.
//
// Phase A item 3.3: implementation of the 8 C-ABI functions. Wraps the existing
// math pipeline (xform_obj / shade_obj / draw_obj via cmodel_core) without
// re-deriving any math. All state is in cmodel_core globals (per README §3),
// ensuring re-entrancy for a single simulation thread.

#include "cmodel_golden.h"
#include "cmodel_core.h"
#include "struct.h"
#include "obj.h"
#include "transform.h"
#include "matrix.h"
#include "mif.h"

#include <stdio.h>
#include <stdlib.h>
#include <stdint.h>
#include <cassert>
#include <vector>

#ifdef CMODEL_HAVE_LIBPNG
#include <png.h>
#endif

/* The return-code tokens (CMODEL_OK, CMODEL_OOM, CMODEL_FILE_ERROR,
 * CMODEL_STATE_ERROR, CMODEL_SELFTEST_NI, CMODEL_FEATURE_UNAVAILABLE) come
 * from cmodel_golden.h. Both C and C++ callers see the same values; this is
 * the canonical source that DPI-C callers import. The previous per-translation-
 * unit re-#define block was removed to avoid shadowing the enum. */

cmodel_rc cmodel_init(int w, int h){
    (void)w; (void)h;
    
    cmodel_reset();
    
    // Allocate framebuffer (V_SIZE x H_SIZE)
    FRAMEBUFFER = (colour**) malloc(sizeof(colour*) * V_SIZE);
    if (!FRAMEBUFFER) return CMODEL_OOM;
    for (int i = 0; i < V_SIZE; i++){
        FRAMEBUFFER[i] = (colour*) calloc(H_SIZE, sizeof(colour));
        if (!FRAMEBUFFER[i]){
            for (int j = 0; j < i; j++) free(FRAMEBUFFER[j]);
            free(FRAMEBUFFER);
            FRAMEBUFFER = nullptr;
            return CMODEL_OOM;
        }
    }
    
    // Allocate z-buffer (V_SIZE x H_SIZE)
    Z_BUFFER = (short_fixed**) malloc(sizeof(short_fixed*) * V_SIZE);
    if (!Z_BUFFER){
        for (int i = 0; i < V_SIZE; i++) free(FRAMEBUFFER[i]);
        free(FRAMEBUFFER);
        FRAMEBUFFER = nullptr;
        return CMODEL_OOM;
    }
    for (int i = 0; i < V_SIZE; i++){
        Z_BUFFER[i] = (short_fixed*) calloc(H_SIZE, sizeof(short_fixed));
        if (!Z_BUFFER[i]){
            for (int j = 0; j < i; j++) free(Z_BUFFER[j]);
            free(Z_BUFFER);
            Z_BUFFER = nullptr;
            for (int j = 0; j < V_SIZE; j++) free(FRAMEBUFFER[j]);
            free(FRAMEBUFFER);
            FRAMEBUFFER = nullptr;
            return CMODEL_OOM;
        }
    }
    
    // Initialize z-buffer to far clip plane (100.0 in Q4.13) per contract C3
    zb_init((SF)100);
    
    TRI = 0;
    CCW = 0;
    PIXEL_COUNT = 0;
    
    return CMODEL_OK;
}

cmodel_rc cmodel_load_mesh(const char *memh_path){
    if (!memh_path) return CMODEL_FILE_ERROR;
    
    FILE *fp = fopen(memh_path, "r");
    if (!fp) return CMODEL_FILE_ERROR;
    
    unsigned int word;
    int n = 0;
    
    // 16 words: COMP_XFORM_MAT (row-major 4x4)
    if (!COMP_XFORM_MAT){
        COMP_XFORM_MAT = (fixed**) malloc(sizeof(fixed*) * 4);
        for (int i = 0; i < 4; i++)
            COMP_XFORM_MAT[i] = (fixed*) malloc(sizeof(fixed) * 4);
    }
    for (int i = 0; i < 4; i++){
        for (int j = 0; j < 4; j++){
            n = fscanf(fp, "%x", &word);
            if (n != 1){ fclose(fp); return CMODEL_FILE_ERROR; }
            COMP_XFORM_MAT[i][j] = F::from_raw_value((int32_t)word);
        }
    }
    
    // 3 words: LIGHT (x, y, z)
    for (int i = 0; i < 3; i++){
        n = fscanf(fp, "%x", &word);
        if (n != 1){ fclose(fp); return CMODEL_FILE_ERROR; }
        fixed val = F::from_raw_value((int32_t)word);
        if (i == 0) LIGHT.x = val;
        else if (i == 1) LIGHT.y = val;
        else LIGHT.z = val;
    }
    LIGHT.w = (F)0;
    LIGHT.xn = LIGHT.yn = LIGHT.zn = (F)0;
    LIGHT.c.red = LIGHT.c.green = LIGHT.c.blue = (F)0;
    
    // 1 word: count (total data words = N_triangles * 21)
    n = fscanf(fp, "%x", &word);
    if (n != 1){ fclose(fp); return CMODEL_FILE_ERROR; }
    uint32_t count = (uint32_t)word;
    if (count % 21 != 0){ fclose(fp); return CMODEL_FILE_ERROR; }
    uint32_t num_vertices = count / 7;
    uint32_t num_triangles = num_vertices / 3;
    
    // Read vertices
    if (OBJ){ delete OBJ; OBJ = nullptr; }
    OBJ = new std::vector<triangle>;
    
    for (uint32_t t = 0; t < num_triangles; t++){
        triangle tri;
        for (int v = 0; v < 3; v++){
            vertex *vp = (v == 0) ? &tri.p0 : (v == 1) ? &tri.p1 : &tri.p2;
            for (int c = 0; c < 7; c++){
                n = fscanf(fp, "%x", &word);
                if (n != 1){ fclose(fp); delete OBJ; OBJ = nullptr; return CMODEL_FILE_ERROR; }
                fixed val = F::from_raw_value((int32_t)word);
                switch (c){
                    case 0: vp->x = val; break;
                    case 1: vp->y = val; break;
                    case 2: vp->z = val; break;
                    case 3: vp->w = val; break;
                    case 4: vp->xn = val; break;
                    case 5: vp->yn = val; break;
                    case 6: vp->zn = val; break;
                }
            }
            vp->c.red = vp->c.green = vp->c.blue = (F)0;
        }
        OBJ->push_back(tri);
    }
    
    fclose(fp);
    return CMODEL_OK;
}

cmodel_rc cmodel_render(void){
    if (!OBJ || OBJ->empty()) return CMODEL_STATE_ERROR;
    if (!COMP_XFORM_MAT) return CMODEL_STATE_ERROR;
    if (!FRAMEBUFFER) return CMODEL_STATE_ERROR;
    
    std::vector<triangle>* local = copy_obj(OBJ);
    if (!local) return CMODEL_OOM;
    
    xform_obj(local, COMP_XFORM_MAT, 1);
    
    if (RASTER_SPACE_OBJ) delete RASTER_SPACE_OBJ;
    RASTER_SPACE_OBJ = local;
    
    TRI = 0;
    CCW = 0;
    PIXEL_COUNT = 0;
    
    shade_obj(RASTER_SPACE_OBJ, &LIGHT);
    draw_obj(RASTER_SPACE_OBJ);
    
    return CMODEL_OK;
}

/* Locked colour contract: 5-bit grey intensity L for a Q13.14 shaded raw.
 * Floor-scaled (raw*31)>>14 with saturating clamp into [0,31]:
 * negative -> 0, > 31 -> 31 (white saturates, never wraps modulo 32).
 * Shared by cmodel_fb_pixel / cmodel_fb_gray / cmodel_save_image for bit-exactness. */
static inline int32_t clamp_gray5(int32_t raw) {
    int32_t cc = (raw * 31) >> 14;
    if (cc < 0)  return 0;
    if (cc > 31) return 31;
    return cc;
}

cmodel_rc cmodel_fb_pixel(int x, int y){
    if (x < 0 || x >= H_SIZE || y < 0 || y >= V_SIZE || !FRAMEBUFFER)
        return 0;
#ifndef NDEBUG
    const colour *px = &FRAMEBUFFER[y][x];
    int32_t r = px->red.raw_value();
    int32_t g = px->green.raw_value();
    int32_t b = px->blue.raw_value();
    // shade_obj (obj.cpp:28-73) sets all three channels to the same dot; verify.
    assert(r == g && r == b);
#endif
    /* 16-bit RGB565 grey: {L[4:0], G6[5:0], L[4:0]} with G6 = {L[4:0], L[4]}
     * (standard MSB replication, green = 6-bit). L=31 -> 0xFFFF (pure white). */
    uint32_t L  = (uint32_t)clamp_gray5(FRAMEBUFFER[y][x].red.raw_value());
    uint32_t G6 = (L << 1) | (L >> 4);
    return (L << 11) | (G6 << 5) | L;
}

cmodel_rc cmodel_fb_gray(int x, int y){
    if (x < 0 || x >= H_SIZE || y < 0 || y >= V_SIZE || !FRAMEBUFFER)
        return 0;
    /* 5-bit grey intensity L in [0,31], format-agnostic. */
    return (uint32_t)clamp_gray5(FRAMEBUFFER[y][x].red.raw_value());
}

cmodel_rc cmodel_z_pixel(int x, int y){
    if (x < 0 || x >= H_SIZE || y < 0 || y >= V_SIZE || !Z_BUFFER)
        return 0;
    return (uint32_t)Z_BUFFER[y][x].raw_value();
}

cmodel_rc cmodel_reset(void){
    if (RASTER_SPACE_OBJ){ delete RASTER_SPACE_OBJ; RASTER_SPACE_OBJ = nullptr; }
    if (OBJ){ delete OBJ; OBJ = nullptr; }
    if (COMP_XFORM_MAT){ mat_delete(COMP_XFORM_MAT, 4); COMP_XFORM_MAT = nullptr; }
    if (PROJ_MAT){ mat_delete(PROJ_MAT, 4); PROJ_MAT = nullptr; }
    if (WRLD_TO_CAM_MAT){ mat_delete(WRLD_TO_CAM_MAT, 4); WRLD_TO_CAM_MAT = nullptr; }
    if (SCALE_TO_RAS_MAT){ mat_delete(SCALE_TO_RAS_MAT, 4); SCALE_TO_RAS_MAT = nullptr; }
    if (FRAMEBUFFER){
        for (int i = 0; i < V_SIZE; i++) free(FRAMEBUFFER[i]);
        free(FRAMEBUFFER);
        FRAMEBUFFER = nullptr;
    }
    if (Z_BUFFER){
        for (int i = 0; i < V_SIZE; i++) free(Z_BUFFER[i]);
        free(Z_BUFFER);
        Z_BUFFER = nullptr;
    }
    LIGHT = {};
    TRI = 0;
    CCW = 0;
    PIXEL_COUNT = 0;
    return CMODEL_OK;
}

/*
 * cmodel_save_image — off-sim image capture.
 *
 * Emits a (H_SIZE x V_SIZE) PNG with the rendered framebuffer contents.
 * The per-pixel computation is the EXACT same C1 formula used by
 * cmodel_fb_pixel, then rescaled 5-bit -> 8-bit grey via cc*255/31 (matching
 * render_gui.py --save's byte formula). Written as an RGB PNG (colortype 2)
 * so the bytes are viewable in any standard decoder; the three channels are
 * identical, so a grey interpretation matches what render_gui.py emits.
 *
 * Behaviour when built without libpng (CMODEL_HAVE_LIBPNG undefined):
 * the function is still present in the .so (returns
 * CMODEL_FEATURE_UNAVAILABLE = 0x7002), making the ABI stable across builds.
 */
#ifdef CMODEL_HAVE_LIBPNG

cmodel_rc cmodel_save_image(const char *path) {
    if (!path || !path[0])                    return CMODEL_FILE_ERROR;
    if (!FRAMEBUFFER)                          return CMODEL_STATE_ERROR;

    /* Allocate a single top-down RGB buffer (3 bytes per pixel). */
    unsigned long  img_bytes = (unsigned long)H_SIZE * V_SIZE * 3;
    unsigned char *row       = (unsigned char*)malloc(img_bytes);
    if (!row)                                     return CMODEL_OOM;

    for (int y = 0; y < V_SIZE; y++) {
        unsigned char *dst = row + (size_t)y * H_SIZE * 3;
        const colour *src  = &FRAMEBUFFER[y][0];
        for (int x = 0; x < H_SIZE; x++) {
            int32_t cc   = clamp_gray5(src[x].red.raw_value());
            uint8_t g8   = (uint8_t)((cc * 255) / 31);
            dst[x * 3 + 0] = g8;
            dst[x * 3 + 1] = g8;
            dst[x * 3 + 2] = g8;
        }
    }

    FILE *fp = fopen(path, "wb");
    if (!fp) { free(row); return CMODEL_FILE_ERROR; }

    png_structp png = png_create_write_struct(PNG_LIBPNG_VER_STRING,
                                              NULL, NULL, NULL);
    if (!png) { fclose(fp); free(row); return CMODEL_FILE_ERROR; }
    png_infop info = png_create_info_struct(png);
    if (!info) {
        png_destroy_write_struct(&png, NULL);
        fclose(fp); free(row);
        return CMODEL_FILE_ERROR;
    }
    if (setjmp(png_jmpbuf(png))) {
        png_destroy_write_struct(&png, &info);
        fclose(fp); free(row);
        return CMODEL_FILE_ERROR;
    }

    png_init_io(png, fp);
    png_set_IHDR(png, info,
                 H_SIZE, V_SIZE,
                 8,                       /* bit depth */
                 PNG_COLOR_TYPE_RGB,      /* 3 channels, identical */
                 PNG_INTERLACE_NONE,
                 PNG_COMPRESSION_TYPE_DEFAULT,
                 PNG_FILTER_TYPE_DEFAULT);
    png_write_info(png, info);

    /* Write the buffer row by row in top-down order. */
    for (int y = 0; y < V_SIZE; y++)
        png_write_row(png, row + (size_t)y * H_SIZE * 3);

    png_write_end(png, info);
    png_destroy_write_struct(&png, &info);
    int rc = fclose(fp);
    free(row);
    return (rc == 0) ? CMODEL_OK : CMODEL_FILE_ERROR;
}

#else  /* !CMODEL_HAVE_LIBPNG — feature compiled out */

cmodel_rc cmodel_save_image(const char *path) {
    (void)path;
    return CMODEL_FEATURE_UNAVAILABLE;
}

#endif  /* CMODEL_HAVE_LIBPNG */

/* =========================================================================
 * Per-vertex query surface + exact-shade reference (ABI major 2).
 * ========================================================================= */

/* Flat index: vertex i = triangle i/3, corner i%3 (p0,p1,p2 order),
 * matching the DUT stream order (the SM streams each triangle's corners
 * in order). */
static const vertex *flat_vertex_at(const std::vector<triangle> *tris, size_t i){
    const triangle &t = tris->at(i / 3);
    switch (i % 3){
        case 0:  return &t.p0;
        case 1:  return &t.p1;
        default: return &t.p2;
    }
}

int cmodel_shade_dot_exact(int lx, int ly, int lz,
                           int nx, int ny, int nz){
    // Exact 64-bit products, ONE arithmetic (floor) shift. Deliberately
    // NOT routed through fpm::fixed: dot_3's per-term round-to-nearest is
    // the locked frame-level behaviour; this is the DUT madd datapath's
    // intended arithmetic (see the header doc for the 3923-vs-3924 example).
    int64_t sum = (int64_t)nx * (int64_t)lx
                + (int64_t)ny * (int64_t)ly
                + (int64_t)nz * (int64_t)lz;
    // Arithmetic right shift = floor division by 2^14 (two's complement,
    // universal on all supported targets); mask to the 27-bit DUT port width.
    int64_t out = (sum >> 14) & 0x7FFFFFF;
    // Sign-extend the 27-bit result into the low 32 bits.
    if (out & 0x4000000)
        out |= ~0x7FFFFFF;
    return (int)out;
}

int cmodel_vertex_count(void){
    if (!OBJ || OBJ->empty())
        return 0;
    return (int)(OBJ->size() * 3);
}

cmodel_rc cmodel_get_vertex_raw(int i, int pos[4], int nrm[3]){
    if (!pos || !nrm || !OBJ || OBJ->empty())
        return CMODEL_STATE_ERROR;
    if ((size_t)i >= OBJ->size() * 3)
        return CMODEL_STATE_ERROR;
    const vertex *v = flat_vertex_at(OBJ, (size_t)i);
    pos[0] = (int)v->x.raw_value();
    pos[1] = (int)v->y.raw_value();
    pos[2] = (int)v->z.raw_value();
    pos[3] = (int)v->w.raw_value();
    nrm[0] = (int)v->xn.raw_value();
    nrm[1] = (int)v->yn.raw_value();
    nrm[2] = (int)v->zn.raw_value();
    return CMODEL_OK;
}

cmodel_rc cmodel_get_vertex_xform(int i, int pos[4]){
    if (!pos || !RASTER_SPACE_OBJ || RASTER_SPACE_OBJ->empty())
        return CMODEL_STATE_ERROR;
    if ((size_t)i >= RASTER_SPACE_OBJ->size() * 3)
        return CMODEL_STATE_ERROR;
    const vertex *v = flat_vertex_at(RASTER_SPACE_OBJ, (size_t)i);
    pos[0] = (int)v->x.raw_value();
    pos[1] = (int)v->y.raw_value();
    pos[2] = (int)v->z.raw_value();
    pos[3] = (int)v->w.raw_value();
    return CMODEL_OK;
}

int cmodel_get_vertex_shade(int i){
    if (!RASTER_SPACE_OBJ || RASTER_SPACE_OBJ->empty())
        return 0;
    if ((size_t)i >= RASTER_SPACE_OBJ->size() * 3)
        return 0;
    // shade_obj stores the dot in all three channels; red is canonical
    // (see the assert in cmodel_fb_pixel).
    return (int)flat_vertex_at(RASTER_SPACE_OBJ, (size_t)i)->c.red.raw_value();
}

cmodel_rc cmodel_write_mesh(const char *path,
                            const int mat[16], const int light[3],
                            const int verts[], int n_vertices){
    if (!path || !path[0] || !mat || !light || !verts || n_vertices <= 0)
        return CMODEL_FILE_ERROR;
    FILE *fp = fopen(path, "w");
    if (!fp)
        return CMODEL_FILE_ERROR;
    for (int i = 0; i < 16; i++)
        fprintf(fp, "%08x\n", (unsigned)(uint32_t)mat[i]);
    for (int i = 0; i < 3; i++)
        fprintf(fp, "%08x\n", (unsigned)(uint32_t)light[i]);
    fprintf(fp, "%08x\n", (unsigned)(uint32_t)(n_vertices * 7));
    for (int i = 0; i < n_vertices * 7; i++)
        fprintf(fp, "%08x\n", (unsigned)(uint32_t)verts[i]);
    int rc = fclose(fp);
    return (rc == 0) ? CMODEL_OK : CMODEL_FILE_ERROR;
}

/* =========================================================================
 * Self-test — the "golden of the golden" (README §7.6).
 *
 * Self-contained known-answer checks: no repo-relative file reads, no
 * framebuffer; valid before cmodel_init. Returns 0 on full match; non-zero
 * is a bitmask of the failed sub-checks:
 *   bit 0 (1): (a) exact-dot known answers under the box light
 *   bit 1 (2): (b) per-term-rounded variant: equals exact for the six unit
 *              normals, and 3924 for (8192,8192,8192) — the documented
 *              exact-vs-rounded divergence, locked as intended
 *   bit 2 (4): (c) seeded sweep: |exact - rounded| <= 3 for 100 random
 *              (light, normal) pairs, components in the per-term-rounded
 *              path's representable range (|raw| <= 2^20)
 *   bit 3 (8): (d) cmodel_write_mesh / cmodel_load_mesh round-trip
 * ========================================================================= */

// Per-term-rounded dot: the exact fpm::fixed ops of obj.cpp dot_3/shade_obj
// (round-to-nearest per product, then plain addition).
static int32_t selftest_dot_rounded(int nx, int ny, int nz,
                                    int lx, int ly, int lz){
    vertex a = {};
    vertex b = {};
    a.xn = F::from_raw_value(nx); a.yn = F::from_raw_value(ny); a.zn = F::from_raw_value(nz);
    b.x  = F::from_raw_value(lx); b.y  = F::from_raw_value(ly); b.z  = F::from_raw_value(lz);
    return dot_3(a, b).raw_value();
}

// Deterministic 32-bit LCG (Numerical Recipes constants) so the sweep is
// reproducible on every platform.
static uint32_t selftest_rng_state = 0;
// Uniform in [-2^20, 2^20-1] raw (see the (c) range justification above).
static int32_t selftest_rand21(void){
    selftest_rng_state = selftest_rng_state * 1664525u + 1013904223u;
    int32_t v = (int32_t)((selftest_rng_state >> 12) & 0xFFFFF); // [0, 2^20)
    if (v & 0x100000) v -= 0x200000;                             // signed 21-bit
    return v;
}

// Read every hex word of a .memh file into *words.
static bool selftest_read_mesh_words(const char *path, std::vector<int32_t> *words){
    FILE *fp = fopen(path, "r");
    if (!fp)
        return false;
    unsigned int w;
    words->clear();
    while (fscanf(fp, "%x", &w) == 1)
        words->push_back((int32_t)w);
    fclose(fp);
    return true;
}

cmodel_rc cmodel_selftest(void){
    // Box light (the light words of tests/testcases/memh/box.memh).
    const int LX = 10711, LY = -10081, LZ = 7217;
    cmodel_rc fail = 0;

    // (a) exact-variant known answers — the four independent hand-computed
    //     vectors under the box light.
    {
        struct { int nx, ny, nz, exp; } ka[] = {
            { -16384,      0,      0, -10711 },
            {      0, -16384,      0,  10081 },
            {   8192,   8192,   8192,   3923 },
            {  -8192,      0,   8192,  -1747 },
            // 27-bit edge (max-magnitude normal): verifies the int64 path at
            // the API's full input range. Hand-computed under the box light:
            // sum = 67108863*(10711+7217) + 67108864*10081
            //     = 2^26*28009 - 17928 = 1879652153848
            // >>14 = 2^12*28009 - 2 = 114724862; 27-bit mask (bit 26 set)
            // -> sign-extend = -19492866.
            { 67108863, -67108864, 67108863, -19492866 },
        };
        for (size_t i = 0; i < sizeof(ka)/sizeof(ka[0]); i++){
            int got = cmodel_shade_dot_exact(LX, LY, LZ, ka[i].nx, ka[i].ny, ka[i].nz);
            if (got != ka[i].exp){
                fail |= 1;
                fprintf(stderr, "selftest (a): dot_exact(%d,%d,%d) = %d, expected %d\n",
                        ka[i].nx, ka[i].ny, ka[i].nz, got, ka[i].exp);
            }
        }
    }

    // (b) per-term-rounded variant: equals the exact variant for the six
    //     unit normals (unit normal * light divides exactly), and 3924 for
    //     (8192,8192,8192) — locking the documented divergence as intended.
    {
        int units[6][3] = {
            { -16384, 0, 0 }, { 16384, 0, 0 },
            { 0, -16384, 0 }, { 0, 16384, 0 },
            { 0, 0, -16384 }, { 0, 0, 16384 },
        };
        for (int i = 0; i < 6; i++){
            int exact   = cmodel_shade_dot_exact(LX, LY, LZ, units[i][0], units[i][1], units[i][2]);
            int rounded = selftest_dot_rounded(units[i][0], units[i][1], units[i][2], LX, LY, LZ);
            if (exact != rounded){
                fail |= 2;
                fprintf(stderr, "selftest (b): unit normal (%d,%d,%d): rounded %d != exact %d\n",
                        units[i][0], units[i][1], units[i][2], rounded, exact);
            }
        }
        int rounded = selftest_dot_rounded(8192, 8192, 8192, LX, LY, LZ);
        if (rounded != 3924){
            fail |= 2;
            fprintf(stderr, "selftest (b): (8192,8192,8192) rounded = %d, expected 3924\n", rounded);
        }
    }

    // (c) seeded consistency sweep: 100 random (light, normal) pairs;
    //     |exact - rounded| <= 3 (3 terms x <=0.5 LSB per-term rounding +
    //     <=0.5 LSB floor-vs-round on the final shift).
    //     Components are bounded to |raw| <= 2^20 (value 64.0): F is
    //     fixed<int32_t, int64_t, 14>, so the per-term-rounded path
    //     overflows once a product exceeds 32-bit Q13.14 (|product| < 2^17
    //     value units); at |raw| <= 2^20 every product raw <= 2^26 and the
    //     3-term sum raw <= 3*2^26, comfortably in range. The exact
    //     function's full 27-bit input range is covered by the (a) edge
    //     vector.
    {
        selftest_rng_state = 0xC0FFEE01u;
        for (int k = 0; k < 100; k++){
            int lx = selftest_rand21(), ly = selftest_rand21(), lz = selftest_rand21();
            int nx = selftest_rand21(), ny = selftest_rand21(), nz = selftest_rand21();
            int exact   = cmodel_shade_dot_exact(lx, ly, lz, nx, ny, nz);
            int rounded = selftest_dot_rounded(nx, ny, nz, lx, ly, lz);
            // Compare in the 27-bit DUT port domain: the Q13.14 sum can
            // exceed 27 bits (up to 3*2^26 raw at the 2^20 bound) and wraps
            // on the port just like vn_o does.
            int r27 = rounded & 0x7FFFFFF;
            if (r27 & 0x4000000) r27 -= 0x8000000;
            int diff = exact - r27;
            if (diff < 0) diff = -diff;
            if (diff > 3){
                fail |= 4;
                fprintf(stderr, "selftest (c): pair %d: L=(%d,%d,%d) N=(%d,%d,%d) exact=%d rounded=%d (diff %d > 3)\n",
                        k, lx, ly, lz, nx, ny, nz, exact, r27, diff);
            }
        }
    }

    // (d) cmodel_write_mesh / cmodel_load_mesh round-trip: the minimal
    //     3-vertex mesh (the loader requires count % 21 == 0, so one
    //     triangle is the minimum) written to a temp path in the process
    //     CWD, read back, and compared word-for-word; then loaded through
    //     the real parser and compared via the query API.
    {
        const int mat[16] = {
            16384, 0, 0, 0,
            0, 16384, 0, 0,
            0, 0, 16384, 0,
            0, 0, 0, 16384,
        };
        const int light[3] = { LX, LY, LZ };
        const int verts[21] = {
            // v0
            1000, -2000, 3000, 16384,  8192, -8192, 0,
            // v1
            -1000, 2000, -3000, 16384,  0, 8192, 8192,
            // v2
            4000, 5000, 6000, 16384,  -8192, 0, 4096,
        };
        const size_t total = 16 + 3 + 1 + 21;
        const char *tmp = "cmodel_selftest_tmp.memh";

        bool bad = false;
        if (cmodel_write_mesh(tmp, mat, light, verts, 3) != CMODEL_OK){
            bad = true;
            fprintf(stderr, "selftest (d): cmodel_write_mesh(%s) failed\n", tmp);
        }
        if (!bad){
            std::vector<int32_t> words;
            if (!selftest_read_mesh_words(tmp, &words) || words.size() != total){
                bad = true;
                fprintf(stderr, "selftest (d): round-trip read failed (%zu of %zu words)\n",
                        words.size(), total);
            } else {
                size_t wi = 0;
                for (int i = 0; i < 16 && !bad; i++)
                    if (words[wi++] != mat[i]) bad = true;
                for (int i = 0; i < 3 && !bad; i++)
                    if (words[wi++] != light[i]) bad = true;
                if (!bad && words[wi++] != 21) bad = true;
                for (int i = 0; i < 21 && !bad; i++)
                    if (words[wi++] != verts[i]) bad = true;
                if (bad)
                    fprintf(stderr, "selftest (d): word mismatch after round-trip\n");
            }
        }
        if (!bad && cmodel_load_mesh(tmp) != CMODEL_OK){
            bad = true;
            fprintf(stderr, "selftest (d): cmodel_load_mesh(%s) failed\n", tmp);
        }
        if (!bad && cmodel_vertex_count() != 3){
            bad = true;
            fprintf(stderr, "selftest (d): vertex count %d != 3 after reload\n",
                    cmodel_vertex_count());
        }
        if (!bad){
            int pos[4], nrm[3];
            for (int v = 0; v < 3 && !bad; v++){
                if (cmodel_get_vertex_raw(v, pos, nrm) != CMODEL_OK){
                    bad = true;
                    break;
                }
                for (int c = 0; c < 7 && !bad; c++)
                    if ((c < 4 ? pos[c] : nrm[c-4]) != verts[v*7 + c])
                        bad = true;
            }
            if (bad)
                fprintf(stderr, "selftest (d): vertex state mismatch after reload\n");
        }
        (void)remove(tmp);
        if (bad) fail |= 8;
    }

    // Leave the C model in a clean state: the round-trip loaded the temp
    // mesh into the shared globals; cmodel_reset() clears them so a
    // subsequent cmodel_run starts from scratch.
    cmodel_reset();

    return fail;
}

cmodel_rc cmodel_version(void){
    return 2;
}
