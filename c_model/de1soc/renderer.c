#include <stdio.h>
#include <stdlib.h>
#include <math.h>
#include <time.h>
#include <intelfpgaup/video.h>

#include "renderer.h"
// #include "animate.h"

int ANI_MODE = 1; // always run in animation mode

extern colour** FRAMEBUFFER;
extern void animate();

// draw a single point to openGL
int ren_fb_write(float x, float y, colour* p){

    int xx = round(x);
    int yy = round(y);

    unsigned short i = (unsigned short) round(0xF * p->red);
    unsigned short j = (unsigned short) round(0x1F * p->red);

    short c = 0;
    c =  (i << 11) | (j << 5) | (i);

    if ( (xx < H_SIZE) && (xx >= 0) && (yy < V_SIZE) && (yy >= 0) ){
        video_pixel (xx, yy, c);
    }
    else
        printf("F_BUFFER: [%d][%d] is out of bounds!\n", xx, yy);

    return 0;

}

void ren_fb_clear(){

    video_clear();

}



void ren_text_write(int x, int y, char* text){

    // char buffer is 80x60. VGA is 320x240
    // common factor is 4

    video_text(x/4, y/4, text);

}

// paint the contents of the framebuffer with an algorithm
void ren_refresh() {

    video_show (); // swap Front/Back to display the cleared buffer

    // loop through framebuffer and draw to OpenGL
    // int x; int y;
    // for (x = 0; x < H_SIZE; x++)
    //     for (y = 0; y < V_SIZE; y++)
    //         gl_point(x, y, &FRAMEBUFFER[y][x]);

}


void start_renderer(int argc, char** argv){

    video_open ( );
    video_erase ( ); // erase any text on the screen
    video_clear ( ); // clear current VGA Back buffer
    video_show ( ); // swap Front/Back to display the cleared buffer
    video_clear ( ); // clear the VGA Back buffer, where we will draw lines

    // animate();
    // video_show();

    while (1){
        // video_show(); // swap Front/Back to display the cleared buffer
        animate();
        // video_show (); // swap Front/Back to display the cleared buffer
    }
    
}
