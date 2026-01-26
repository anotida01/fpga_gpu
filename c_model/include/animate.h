
#ifndef __ANIMATE_H__
#define __ANIMATE_H__

#include <vector>
#include "struct.h"

void rotate_2d(vertex* v, fixed radians);
void rotate_3d(std::vector<triangle>* object, vertex* light, fixed alpha, fixed beta, fixed gamma);

#ifdef __cplusplus
extern "C" {
#endif
 
void animate();

extern fixed ALPHA_X, BETA_Y, GAMMA_Z;
extern vertex XFORMED_LIGHT;

#ifdef __cplusplus
}
#endif

extern int CCW;
extern int TRI;

#endif

