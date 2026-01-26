#include <stdio.h>
#include <stdlib.h>
#include <math.h>
#include <time.h>

#include "renderer.h"
#include "struct.h"
#include "main.h"
#include "obj.h"
#include "matrix.h"
#include "transform.h"
#include "animate.h"
#include "algorithms.h"

#define FALSE 0
#define TRUE 1

fixed ALPHA_X = (F)0, BETA_Y = (F)0, GAMMA_Z = (F)0;
vertex XFORMED_LIGHT = LIGHT;

int CCW;
int TRI;


void rotate_2d(vertex* v, fixed radians){

    fixed x0 = v->x, y0 = v->y;

    fixed tx_mat[2][2] = {
        {   cos(radians), sin(radians)},
        {-1*sin(radians), cos(radians)}
    };
    fixed** tx_mat_ptr = mat_stk_to_heap_2x2(tx_mat);

    fixed x0_n, y0_n;
    fixed in_vec[2], out_vec[2];
    
    in_vec[0] = x0; in_vec[1]= y0;
    mat_vec_mul(tx_mat_ptr, in_vec, out_vec, 2);
    x0_n = out_vec[0]; y0_n = out_vec[1];

    v->x = x0_n; v->y = y0_n;

    mat_delete(tx_mat_ptr, 2);
    return;

}


// rotate using euler angles
void rotate_3d(std::vector<triangle>* object, vertex* light, fixed alpha, fixed beta, fixed gamma){

    ALPHA_X+=alpha;
    BETA_Y+=beta;
    GAMMA_Z+=gamma;

    fixed** rot_mat_3x3 = gen_rotate_mat_3d(ALPHA_X, BETA_Y, GAMMA_Z);

    fixed rot_mat_4x4_stk[4][4] = {
        {rot_mat_3x3[0][0]  , rot_mat_3x3[0][1] , rot_mat_3x3[0][2] , (F)0},
        {rot_mat_3x3[1][0]  , rot_mat_3x3[1][1] , rot_mat_3x3[1][2] , (F)0},
        {rot_mat_3x3[2][0]  , rot_mat_3x3[2][1] , rot_mat_3x3[2][2] , (F)0},
        {(F)0               , (F)0              , (F)0              , (F)1}
    };

    fixed** rot_mat_4x4 = mat_stk_to_heap_4x4(rot_mat_4x4_stk);
    fixed** rot_mat_4x4_inv  =  mat_stk_to_heap_4x4(rot_mat_4x4_stk);
    fixed** xform_mat  =  mat_stk_to_heap_4x4(rot_mat_4x4_stk);
    inv_mat_4x4(rot_mat_4x4, rot_mat_4x4_inv);

    mat_mul(COMP_XFORM_MAT, rot_mat_4x4, xform_mat, 4);

    // xform_obj(object, rot_mat_4x4, 0);
    xform_obj(object, xform_mat, 1);
    xform_vertex(rot_mat_4x4_inv, light);
    XFORMED_LIGHT = *light; // save this transformed light for later

    mat_delete(rot_mat_3x3, 3);
    mat_delete(rot_mat_4x4, 4);
    mat_delete(rot_mat_4x4_inv, 4);

}


double clk_to_ms(clock_t ticks){
    // units/(units/time) => time (seconds) * 1000 = milliseconds
    return (ticks/(double)CLOCKS_PER_SEC)*1000.0;
}


void animate(){

    if (ANI_MODE == FALSE) return;

    static int num_frames = 0;
    static float render_time = 0;
    static float avg_frame_time;
    clock_t delta_time = 0;

    clock_t start_frame = clock();

        fixed alpha = (F)(0.6 * M_PI/180);
        fixed gamma = (F)(0.3 * M_PI/180);

        ren_fb_clear();
        zb_init((SF)100);

        std::vector<triangle>* object = copy_obj(OBJ);        

        rotate_2d(&LIGHT, alpha/4);
        vertex light = LIGHT;
        rotate_3d(object, &light, alpha, (F)0, gamma);
        
        // scale_to_raster_obj(object);

        delete RASTER_SPACE_OBJ;
        RASTER_SPACE_OBJ = copy_obj(object);

        shade_obj(object, &light);
        TRI = 0; CCW = 0;
        draw_obj(object);
        delete object;

    clock_t end_frame = clock();

    delta_time = end_frame - start_frame;
    render_time += clk_to_ms(delta_time);
    num_frames++;

    if (render_time >= 1000){
        avg_frame_time = render_time / num_frames;
        render_time = 0;
        num_frames = 0;
    }

    char text[BUFSIZ];
    sprintf(text, "Frame Time: %6.3fms", avg_frame_time);
    ren_text_write(10, 10, text);
    ren_refresh();

    // printf("TRI: %d CCW: %d\n", TRI, CCW);

    // sprintf(text, "FPS: %6.3fFPS", 1000/(avg_frame_time));
    // u_text = (unsigned char*) text;
    // GL_FLUSH = 1; gl_text(u_text, 10, 20);

    return;

}

