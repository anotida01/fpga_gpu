
#ifndef CMODEL_CORE_H
#define CMODEL_CORE_H

#include <vector>
#include "struct.h"

// Framebuffer dimensions (moved here from renderer.h so the headless
// cmodel_golden target owns them independent of any display code).
#define V_SIZE 240
#define H_SIZE 320

// Pure framebuffer pixel write (no GL side-effects by default). A display
// target may install a pixel hook to additionally draw the pixel into the GL
// canvas; the headless cmodel_golden target installs no hook, so fb_write is a
// pure math op on FRAMEBUFFER.
int   fb_write(float x, float y, colour *p);

// Z-buffer access (moved here from main.cpp; pure math on Z_BUFFER).
void        zb_init(short_fixed value);
short_fixed zb_read(int x, int y);
void        zb_write(int x, int y, short_fixed z_value);

// Shared renderer state (definitions live in cmodel_core.cpp). Previously the
// definitions of these were scattered across main.cpp / animate.cpp so the
// pure-math translation units could not link standalone; they now have a
// single owner that both the display and the headless targets share.
extern colour**            FRAMEBUFFER;
extern short_fixed**       Z_BUFFER;
extern vertex              LIGHT;
extern std::vector<triangle>* OBJ;
extern std::vector<triangle>* RASTER_SPACE_OBJ;
extern fixed**             PROJ_MAT;
extern fixed**             WRLD_TO_CAM_MAT;
extern fixed**             SCALE_TO_RAS_MAT;
extern fixed**             COMP_XFORM_MAT;
extern int                 TRI;
extern int                 CCW;

// A per-frame pixel hook (installed by the display target ONLY) lets it draw
// each plotted pixel into the GL canvas, preserving live animation, while the
// framebuffer math stays shared. The headless target installs no hook.
typedef int (*cmodel_pixel_hook)(int x, int y, const colour *p);
void cmodel_set_pixel_hook(cmodel_pixel_hook fn);

#endif
