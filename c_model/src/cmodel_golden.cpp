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

cmodel_rc cmodel_selftest(void){
    return CMODEL_SELFTEST_NI;
}

cmodel_rc cmodel_version(void){
    return 1;
}
