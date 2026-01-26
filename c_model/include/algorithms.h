#ifndef __ALGO_H__
#define __ALGO_H__

#include "struct.h"

// EDIT HERE - ALGORITHMS
void draw_triangle(triangle* t);
void transform_rotate(triangle* t, fixed radians, fixed centre_x, fixed centre_y);
void find_bounding_box(triangle* t, int* max_x, int* max_y, int* min_x, int* min_y);
void transform_scale(triangle* t, fixed scale, fixed centre_x, fixed centre_y);
void xform_mat_4x4(triangle* t, fixed** matrix);
fixed** gen_rotate_mat_3d (fixed alpha_x, fixed beta_y, fixed gamma_z);

// #ifndef max
// #define max(a,b) (((a) > (b)) ? (a) : (b))
// #endif

// #ifndef min
// #define min(a,b) (((a) < (b)) ? (a) : (b))
// #endif

#endif