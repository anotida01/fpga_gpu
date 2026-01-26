#ifndef __XFORM_H__
#define __XFORM_H__

#include <vector>
#include <string>
#include "struct.h"

void xform_vertex(fixed** matrix, vertex* v);
fixed** xform_world_to_camera_mat(vertex camera, fixed alpha_x, fixed beta_y, fixed gamma_z);
void xform_obj(std::vector<triangle>* triangles, fixed** matrix, int normalize);
fixed** xform_projection_mat();


#endif
