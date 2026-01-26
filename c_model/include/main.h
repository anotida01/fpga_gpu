
#ifndef __MAIN_H__
#define __MAIN_H__

#include "struct.h"
#include <stdint.h>
#include <vector>

extern colour** FRAMEBUFFER;
extern short_fixed** Z_BUFFER;
extern vertex LIGHT;
extern std::vector<triangle>* OBJ;
extern std::vector<triangle>* RASTER_SPACE_OBJ;
extern fixed** PROJ_MAT;
extern fixed** WRLD_TO_CAM_MAT;
extern fixed** COMP_XFORM_MAT; // composite xform matrix. PROJ_MAT * WRLD_TO_CAM_MAT

short_fixed zb_read(int x, int y);
void zb_write(int x, int y, short_fixed z_value);
void zb_init(short_fixed value);

#endif
