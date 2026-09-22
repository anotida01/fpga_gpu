#ifndef __OBJ_H__
#define __OBJ_H__

#include <vector>
#include <string>
#include "struct.h"

extern long PIXEL_COUNT;

void print_triangles(std::vector<triangle>* triangles);
std::vector<triangle>* load_obj(std::string obj_path);
void draw_obj(std::vector<triangle>* triangles);
// Per-term-rounded directional diffuse: a.xn*b.x + a.yn*b.y + a.zn*b.z with
// one round-to-nearest per product (fpm::fixed), then plain addition.
// The locked frame-level math (see cmodel_shade_dot_exact in
// cmodel_golden.h for the exact-variant relationship).
fixed dot_3(vertex a, vertex b);
void shade_obj(std::vector<triangle>* triangles, vertex* light);
void scale_to_raster_obj(std::vector<triangle>* triangles);

std::vector<triangle>* copy_obj(std::vector<triangle>*);

#endif
