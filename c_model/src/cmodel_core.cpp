
// cmodel_core.cpp
//
// Single owner of the shared renderer state (globals, TRI/CCW counters, the
// z-buffer accessors) and the pure framebuffer pixel writer. Both the display
// target (glut_keyhandling) and the headless cmodel_golden SHARED lib link
// this translation unit — this is what lets the pure-math TUs (transform.cpp,
// obj.cpp, algorithms.cpp, mif.cpp) link in either context without duplicating
// definitions.
//
// The only display-related behavior is the pixel hook: fb_write is a pure
// FRAMEBUFFER write by default. A display target may install a hook to also
// draw the pixel to GL (live animation in the window); the headless target
// installs no hook. The math on FRAMEBUFFER is bit-identical to the previous
// renderer.cpp::ren_fb_write body (which did exactly this write and then
// called gl_point; we moved the write here and the gl_point to the hook).

#include "cmodel_core.h"
#include <math.h>   // round()

// -- shared state definitions (moved from main.cpp:24-32, animate.cpp:21-22) --
colour**            FRAMEBUFFER;
short_fixed**       Z_BUFFER;
vertex              LIGHT;
std::vector<triangle>* OBJ;
std::vector<triangle>* RASTER_SPACE_OBJ;
fixed**             PROJ_MAT;
fixed**             WRLD_TO_CAM_MAT;
fixed**             SCALE_TO_RAS_MAT;
fixed**             COMP_XFORM_MAT;
int                 TRI;
int                 CCW;

// -- z-buffer accessors (moved from main.cpp:38-70) --
void zb_init(short_fixed value){
    for (size_t x = 0; x < H_SIZE; x++)
        for (size_t y = 0; y < V_SIZE; y++)
            Z_BUFFER[y][x] = value;
}

short_fixed zb_read(int x, int y){
    if ( (x < H_SIZE) && (x >= 0) && (y < V_SIZE) && (y >= 0) )
        return Z_BUFFER[y][x];
    return (SF)0;
}

void zb_write(int x, int y, short_fixed z_value){
    if ( (x < H_SIZE) && (x >= 0) && (y < V_SIZE) && (y >= 0) )
        Z_BUFFER[y][x] = z_value;
}

// -- framebuffer pixel write (moved from renderer.cpp:88-106, minus gl_point) --
static cmodel_pixel_hook _pixel_hook = nullptr;

void cmodel_set_pixel_hook(cmodel_pixel_hook fn){
    _pixel_hook = fn;
}

int fb_write(float x, float y, colour *p){
    int xx = round(x), yy = round(y);
    if ( (xx < H_SIZE) && (xx >= 0) && (yy < V_SIZE) && (yy >= 0) ){
        FRAMEBUFFER[yy][xx] = *p;
        if (_pixel_hook) _pixel_hook(xx, yy, p);
        return 0;
    }
    return 1;
}
