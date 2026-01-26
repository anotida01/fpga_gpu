#ifndef __RENDER_H__
#define __RENDER_H__

#include "struct.h"

// Vertical & Horizontal sizes in pixels
#define V_SIZE 240
#define H_SIZE 320

#ifdef __cplusplus
extern "C"
{
#endif

    int ren_fb_write (float x, float y, colour *p);
    void ren_text_write(int x, int y, char* text);
    void ren_fb_clear();
    void ren_refresh();
    void start_renderer(int argc, char** argv);

#ifdef __cplusplus
}
#endif

extern int ANI_MODE;
extern int REN_REFRESH_CLR;


#endif