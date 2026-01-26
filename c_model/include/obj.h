#ifndef __OBJ_H__
#define __OBJ_H__

#include <vector>
#include <string>
#include "struct.h"

extern long PIXEL_COUNT;

void print_triangles(std::vector<triangle>* triangles);
std::vector<triangle>* load_obj(std::string obj_path);
void draw_obj(std::vector<triangle>* triangles);
void shade_obj(std::vector<triangle>* triangles, vertex* light);
void scale_to_raster_obj(std::vector<triangle>* triangles);

std::vector<triangle>* copy_obj(std::vector<triangle>*);

#endif
