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

#define CMODEL_OK            0
#define CMODEL_OOM           1
#define CMODEL_FILE_ERROR    2
#define CMODEL_STATE_ERROR   3
#define CMODEL_SELFTEST_NI   0x7001

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
    
    int32_t raw = FRAMEBUFFER[y][x].red.raw_value();
    int32_t cc = (raw * 31) >> 14;
    if (cc < 0) return 0;
    return (uint32_t)(cc << 10) | (uint32_t)(cc << 5) | (uint32_t)cc;
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

cmodel_rc cmodel_selftest(void){
    return CMODEL_SELFTEST_NI;
}

cmodel_rc cmodel_version(void){
    return 1;
}
