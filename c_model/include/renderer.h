#ifndef __RENDER_H__
#define __RENDER_H__

#include "struct.h"
#include "cmodel_core.h"   // fb_write, H_SIZE, V_SIZE, shared state

// Display-only entry points (GL/GLUT).
void ren_text_write(int x, int y, char* text);
void ren_fb_clear();
void ren_refresh();
void start_renderer(int argc, char** argv);

extern int ANI_MODE;
extern int REN_REFRESH_CLR;

#endif
