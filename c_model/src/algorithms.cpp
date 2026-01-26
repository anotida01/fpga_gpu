// #include <math.h>
#include <stdio.h>
#include <stdlib.h>

#include "main.h"
#include "struct.h"
#include "matrix.h"
#include "xiaolin.h"
#include "obj.h"
#include "renderer.h"
#include "algorithms.h"
#include "animate.h"

// return the bounding box of the trinangle
void find_bounding_box(triangle* t, int* max_x, int* max_y, int* min_x, int* min_y){
    fixed x0 = t->p0.x, y0 = t->p0.y;
    fixed x1 = t->p1.x, y1 = t->p1.y; 
    fixed x2 = t->p2.x, y2 = t->p2.y;

    // find bounding box
    *max_x = (int) std::max( x2, std::max(x1, x0) );
    *min_x = (int) std::min( x2, std::min(x1, x0) );
    *max_y = (int) std::max( y2, std::max(y1, y0) );
    *min_y = (int) std::min( y2, std::min(y1, y0) );

    return;
}


// Bresenham Line Algorithm
void _brens_line(int x1, int y1, int x2, int y2, int dx, int dy, int swap_xy, colour p) {
    //diff is initial decision making parameter
    //Note:x1&y1,x2&y2, dx&dy values are interchanged
    //and passed in _brens_line function so
    //it can handle both cases when m>1 & m<1

    int diff = 2 * dy - dx;

    for (int i = 0; i <= dx; i++){

        // printf("%d, %d\n", x1, y1);

        if (diff < 0) {
            //swap_xy value will decide to plot
            //either x1 or y1 in x's position
            if (swap_xy == 0)
                ren_fb_write(x1, y1, &p);
            else 
                ren_fb_write(y1, x1, &p); //(y1,x1) is passed in xt

            diff = diff + 2 * dy;
        }
        else {
            
            if (swap_xy == 0)
                ren_fb_write(x1, y1, &p);
            else
                ren_fb_write(y1, x1, &p);
            
            //checking either to decrement or increment x
            y1 < y2 ? y1++ : y1--;

            diff = diff + 2 * dy - 2 * dx;
        }

        //checking either to decrement or increment x
        x1 < x2 ? x1++ : x1--;

    }
}


void drawLine(int x1, int y1, int x2, int y2, colour p){

    int dx, dy;

    dx = abs(x2 - x1);
    dy = abs(y2 - y1);

    //if slope is less than one
    if (dx > dy){
        //passing argument as 0 to plot(x,y)
        _brens_line(x1, y1, x2, y2, dx, dy, 0, p);
    }
    else { //if slope is greater than or equal to 1
        //passing argument as 1 to plot (y,x)
        _brens_line(y1, x1, y2, x2, dy, dx, 1, p);
    }

}


// assumes points are ordered in CCW
// https://erkaman.github.io/posts/fast_triangle_rasterization.html
int half_plane_test(int x0, int y0, int x1, int y1, int x2, int y2, int px, int py){

    int passed = 0;

    int t0 = (x1 - x0)*(py - y0) - (y1 - y0)*(px - x0); // (v1 - v0) X (p - v0)
    int t1 = (x2 - x1)*(py - y1) - (y2 - y1)*(px - x1); // (v0 - v2) X (p - v2)
    int t2 = (x0 - x2)*(py - y2) - (y0 - y2)*(px - x2); // (v2 - v1) X (p - v1)

    if (t0 > 0 && t1 > 0 && t2 > 0)
        passed = 1;

    return passed;

}


// TODO: Combine edge function & half plane test
// EXACT SAME AS HALF PLANE TEST
fixed edgeFunction(const vertex &a, const vertex &b, const vertex &c){ 
    return ((F)c.x - (F)a.x) * ((F)b.y - (F)a.y) - ((F)c.y - (F)a.y) * ((F)b.x - (F)a.x); // CW
    // return (b.x - a.x) * (c.y - a.y) - (b.y - a.y) * (c.x - a.x); // CCW
}


void draw_triangle(triangle* t){

    TRI++;

    vertex v0 = t->p0;
    vertex v1 = t->p1; 
    vertex v2 = t->p2;

    // Precompute reciprocal of vertex z-coordinate
    v0.z = (F)1 / v0.z,
    v1.z = (F)1 / v1.z,
    v2.z = (F)1 / v2.z;

    colour c0 = v0.c;
    colour c1 = v1.c;
    colour c2 = v2.c;

    // c0.red = (c0.red + 1)/2.0; c0.green = (c0.green + 1)/2.0; c0.blue = (c0.blue + 1)/2.0;
    // c1.red = (c1.red + 1)/2.0; c1.green = (c1.green + 1)/2.0; c1.blue = (c1.blue + 1)/2.0;
    // c2.red = (c2.red + 1)/2.0; c2.green = (c2.green + 1)/2.0; c2.blue = (c2.blue + 1)/2.0;

    // find bounding box
    int max_x, min_x, max_y, min_y;
    find_bounding_box(t, &max_x, &max_y, &min_x, &min_y);

    // // draw bounding box
    // drawLine(min_x, min_y, max_x, min_y, green);
    // drawLine(max_x, min_y, max_x, max_y, green);
    // drawLine(max_x, max_y, min_x, max_y, green);
    // drawLine(min_x, max_y, min_x, min_y, green);

    // determine if the points are CW or CCW
    // https://www.geeksforgeeks.org/orientation-3-ordered-points/
    fixed val = (v2.x - v1.x)*(v1.y - v0.y) - (v1.x - v0.x)*(v2.y - v1.y);
    if (val < (F)0) { // swap if ccw
        // printf("Counter Clock-wise\n");
        CCW++;
        vertex v_tmp = v1;
        v1 = v2;
        v2 = v_tmp;
    }
    // } else if (val == 0)
        // printf("Linear\n");
    // else
        // printf("Clockwise\n");

    // draw the triangle outline - wireframe render
    // colour cx = {.red=1, .green=1, .blue=1};
    // drawLine(x0, y0, x1, y1, cx);
    // drawLine(x1, y1, x2, y2, cx);
    // drawLine(x2, y2, x0, y0, cx);

    // Z-Buffer Interpolation Must Happen Here!
    // fill the triangle
    // TODO: Rewrite depth test to be more optimized per triangle
    //https://www.scratchapixel.com/lessons/3d-basic-rendering/rasterization-practical-implementation/rasterization-practical-implementation

    fixed area = edgeFunction(v0, v1, v2);

    for (int i = min_x; i <= max_x; i++){

        if (i < 0 || i > H_SIZE) continue;

        for (int j = min_y; j <= max_y; j++){

            if (j < 0 || j > V_SIZE) continue;

            vertex test_v; test_v.x = (F)(i+0.5f); test_v.y = (F)(j+0.5f); test_v.z=(F)0;

            fixed w0 = edgeFunction(v1, v2, test_v);
            fixed w1 = edgeFunction(v2, v0, test_v);
            fixed w2 = edgeFunction(v0, v1, test_v);

            // half plane test
            if (w0 >= (F)0 && w1 >= (F)0 && w2 >= (F)0) {

                if (area == (F)0) area = (F)pow(2, -14);

                w0 /= area;
                w1 /= area;
                w2 /= area;

                fixed oneOverZ = (F)v0.z * w0 + (F)v1.z * w1 + (F)v2.z * w2;
                fixed z_depth;

                if (oneOverZ == (F)0) oneOverZ = (F)pow(2, -14);
                z_depth = (F)1 / oneOverZ;

                // if (oneOverZ != (F)0)
                //     z_depth = (F)1 / oneOverZ;
                // else
                //     z_depth = (F)100;

                if ((SF)z_depth <= zb_read(i, j)){

                    // colour value of pixel
                    fixed r = (F)w0 * c0.red   + (F)w1 * c1.red   + (F)w2 * c2.red; 
                    fixed g = (F)w0 * c0.green + (F)w1 * c1.green + (F)w2 * c2.green; 
                    fixed b = (F)w0 * c0.blue  + (F)w1 * c1.blue  + (F)w2 * c2.blue; 

                    colour c; c.red=r; c.green=g; c.blue=b;

                    zb_write(i, j, (SF)z_depth);
                    ren_fb_write(i, j, &c);
                    PIXEL_COUNT++;
                }

            }

        }
    }


    return;

}


// generate rotation matrix for a rotation of:
// alpha about x, beta about y, gamma about z
// euler angles, they must be in radians!
fixed** gen_rotate_mat_3d (fixed alpha_x, fixed beta_y, fixed gamma_z){
    fixed mat_stk[3][3] = {
        {cos(beta_y)*cos(gamma_z),  sin(alpha_x)*sin(beta_y)*cos(gamma_z) - cos(alpha_x)*sin(gamma_z),
        cos(alpha_x)*sin(beta_y)*cos(gamma_z) + sin(alpha_x)*sin(gamma_z)},

        {cos(beta_y)*sin(gamma_z),  sin(alpha_x)*sin(beta_y)*sin(gamma_z) + cos(alpha_x)*cos(gamma_z),
        cos(alpha_x)*sin(beta_y)*cos(gamma_z) - sin(alpha_x)*cos(gamma_z)},

        {-sin(beta_y), sin(alpha_x)*cos(beta_y), cos(alpha_x)*cos(beta_y)},
    };

    fixed** mat = mat_stk_to_heap_3x3(mat_stk); // copy input matrix to heap

    return mat;

    // The other rotation matrix on Wikipedia
    // fixed camera_to_world_stk[4][4] = {
    //     {cos(alpha_x)*cos(beta_y),  cos(alpha_x)*sin(beta_y)*sin(gamma_z) - sin(alpha_x)*cos(gamma_z),
    //     cos(alpha_x)*sin(beta_y)*cos(gamma_z) + sin(alpha_x)*sin(gamma_z), camera.x},

    //     {sin(alpha_x)*cos(beta_y),  sin(alpha_x)*sin(beta_y)*sin(gamma_z) + cos(alpha_x)*cos(gamma_z),
    //     sin(alpha_x)*sin(beta_y)*cos(gamma_z) - cos(alpha_x)*sin(gamma_z), camera.y},

    //     {-sin(beta_y), cos(beta_y)*sin(gamma_z), cos(beta_y)*cos(gamma_z), camera.z},

    //     {0, 0, 0, 1}
    // };

}


// rotate trinagle about viewport centre
void transform_rotate(triangle* t, fixed radians, fixed centre_x, fixed centre_y){
    
    fixed x0 = t->p0.x, y0 = t->p0.y;
    fixed x1 = t->p1.x, y1 = t->p1.y; 
    fixed x2 = t->p2.x, y2 = t->p2.y;

    // translate to origin from centre rotation
    x0 -= centre_x; x1 -= centre_x; x2 -= centre_x; 
    y0 -= centre_y; y1 -= centre_y; y2 -= centre_y; 

    // transform matrix
    fixed tx_mat[2][2] = {
        {   cos(radians), sin(radians)},
        {-1*sin(radians), cos(radians)}
    };
    fixed** tx_mat_ptr = mat_stk_to_heap_2x2(tx_mat);

    fixed x0_n, y0_n, x1_n, y1_n, x2_n, y2_n;
    fixed in_vec[2], out_vec[2];
    
    in_vec[0] = x0; in_vec[1]= y0;
    mat_vec_mul(tx_mat_ptr, in_vec, out_vec, 2);
    x0_n = out_vec[0]; y0_n = out_vec[1];

    in_vec[0] = x1; in_vec[1]= y1;
    mat_vec_mul(tx_mat_ptr, in_vec, out_vec, 2);
    x1_n = out_vec[0]; y1_n = out_vec[1];

    in_vec[0] = x2; in_vec[1]= y2;
    mat_vec_mul(tx_mat_ptr, in_vec, out_vec, 2);
    x2_n = out_vec[0]; y2_n = out_vec[1];


    // translate to centre rotation from origin
    x0_n += centre_x; x1_n += centre_x; x2_n += centre_x;
    y0_n += centre_y; y1_n += centre_y; y2_n += centre_y;    

    // update triangle
    // t->p0.x = round(x0_n); t->p1.x = round(x1_n); t->p2.x = round(x2_n); 
    // t->p0.y = round(y0_n); t->p1.y = round(y1_n); t->p2.y = round(y2_n);
    t->p0.x = x0_n; t->p1.x = x1_n; t->p2.x = x2_n; 
    t->p0.y = y0_n; t->p1.y = y1_n; t->p2.y = y2_n;

    mat_delete(tx_mat_ptr, 2);

    return;

}


void transform_scale(triangle* t, fixed scale, fixed centre_x, fixed centre_y){

    fixed x0 = t->p0.x, y0 = t->p0.y;
    fixed x1 = t->p1.x, y1 = t->p1.y; 
    fixed x2 = t->p2.x, y2 = t->p2.y;
    // colour p = t->p0.c;

    // translate to origin from centre rotation
    x0 -= centre_x; x1 -= centre_x; x2 -= centre_x; 
    y0 -= centre_y; y1 -= centre_y; y2 -= centre_y; 

    // transform matrix
    fixed tx_mat[2][2] = {
        { scale,  (F)0 },
        {  (F)0, scale }
    };
    fixed** tx_mat_ptr = mat_stk_to_heap_2x2(tx_mat);

    fixed x0_n, y0_n, x1_n, y1_n, x2_n, y2_n;
    fixed in_vec[2], out_vec[2];
    
    in_vec[0] = x0; in_vec[1]= y0;
    mat_vec_mul(tx_mat_ptr, in_vec, out_vec, 2);
    x0_n = out_vec[0]; y0_n = out_vec[1];

    in_vec[0] = x1; in_vec[1]= y1;
    mat_vec_mul(tx_mat_ptr, in_vec, out_vec, 2);
    x1_n = out_vec[0]; y1_n = out_vec[1];

    in_vec[0] = x2; in_vec[1]= y2;
    mat_vec_mul(tx_mat_ptr, in_vec, out_vec, 2);
    x2_n = out_vec[0]; y2_n = out_vec[1];

    // translate to centre rotation from origin
    x0_n += centre_x; x1_n += centre_x; x2_n += centre_x;
    y0_n += centre_y; y1_n += centre_y; y2_n += centre_y;    

    // update triangle
    t->p0.x = x0_n; t->p1.x = x1_n; t->p2.x = x2_n; 
    t->p0.y = y0_n; t->p1.y = y1_n; t->p2.y = y2_n;

    mat_delete(tx_mat_ptr, 2);

    return;

}