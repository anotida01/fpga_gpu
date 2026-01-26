
#include <math.h>

#include "matrix.h"
#include "transform.h"
#include "main.h"

void xform_vertex(fixed** matrix, vertex* v){

    fixed x0 = v->x, y0 = v->y, z0 = v->z, w0 = v->w;

    fixed x0_n, y0_n, z0_n, w0_n; 
    fixed in_vec[4], out_vec[4];
    
    in_vec[0] = x0; in_vec[1]= y0; in_vec[2]= z0; in_vec[3]= w0;
    mat_vec_mul(matrix, in_vec, out_vec, 4);
    x0_n = out_vec[0]; y0_n = out_vec[1]; z0_n = out_vec[2]; w0_n = out_vec[3];

    v->x = x0_n; v->y = y0_n; v->z = z0_n, v->w = w0_n;

    return;
}

void xform_mat_4x4(triangle* t, fixed** matrix, int norm){

    fixed x0 = t->p0.x, y0 = t->p0.y, z0 = t->p0.z, w0 = t->p0.w;
    fixed x1 = t->p1.x, y1 = t->p1.y, z1 = t->p1.z, w1 = t->p1.w; 
    fixed x2 = t->p2.x, y2 = t->p2.y, z2 = t->p2.z, w2 = t->p2.w;
    // colour p = t->p0.c;

    fixed x0_n, y0_n, z0_n, w0_n; 
    fixed x1_n, y1_n, z1_n, w1_n; 
    fixed x2_n, y2_n, z2_n, w2_n;
    fixed in_vec[4], out_vec[4];
    
    in_vec[0] = x0; in_vec[1]= y0; in_vec[2]= z0; in_vec[3]= w0;
    mat_vec_mul(matrix, in_vec, out_vec, 4);
    x0_n = out_vec[0]; y0_n = out_vec[1]; z0_n = out_vec[2]; w0_n = out_vec[3];

    in_vec[0] = x1; in_vec[1]= y1; in_vec[2]= z1; in_vec[3]= w1;
    mat_vec_mul(matrix, in_vec, out_vec, 4);
    x1_n = out_vec[0]; y1_n = out_vec[1]; z1_n = out_vec[2]; w1_n = out_vec[3];

    in_vec[0] = x2; in_vec[1]= y2; in_vec[2]= z2; in_vec[3]= w2;
    mat_vec_mul(matrix, in_vec, out_vec, 4);
    x2_n = out_vec[0]; y2_n = out_vec[1]; z2_n = out_vec[2]; w2_n = out_vec[3];

    // translate to centre rotation from origin
    // x0_n += centre_x; x1_n += centre_x; x2_n += centre_x;
    // y0_n += centre_y; y1_n += centre_y; y2_n += centre_y;

    // normalize if necessary
    // if (norm){
    //     if (fabs(w0_n - 1.0) > __FLT_EPSILON__){
    //         x0_n /= w0_n; y0_n /= w0_n; z0_n /= w0_n; w0_n /= w0_n;
    //     }
    //     if (fabs(w1_n - 1.0) > __FLT_EPSILON__){
    //         x1_n /= w1_n; y1_n /= w1_n; z1_n /= w1_n; w1_n /= w1_n;
    //     }
    //     if (fabs(w2_n - 1.0) > __FLT_EPSILON__){
    //         x2_n /= w2_n; y2_n /= w2_n; z2_n /= w2_n; w2_n /= w2_n;
    //     }
    // }

    if (norm){
        if (w0_n != (F)1){
            x0_n /= w0_n; y0_n /= w0_n; z0_n /= w0_n; w0_n /= w0_n;
        }
        if (w1_n != (F)1){
            x1_n /= w1_n; y1_n /= w1_n; z1_n /= w1_n; w1_n /= w1_n;
        }
        if (w2_n != (F)1){
            x2_n /= w2_n; y2_n /= w2_n; z2_n /= w2_n; w2_n /= w2_n;
        }
    }

    // update triangle
    t->p0.x = x0_n; t->p1.x = x1_n; t->p2.x = x2_n; 
    t->p0.y = y0_n; t->p1.y = y1_n; t->p2.y = y2_n;
    t->p0.z = z0_n; t->p1.z = z1_n; t->p2.z = z2_n;
    t->p0.w = w0_n; t->p1.w = w1_n; t->p2.w = w2_n;

}

void xform_obj(std::vector<triangle>* triangles, fixed** matrix, int normalize){

    triangle t;

    for (size_t i = 0; i < triangles->size(); i++){
        t = triangles->at(i);
        xform_mat_4x4(&t, matrix, normalize);
        triangles->at(i) = t;
    }

}


// generate world_to_camera matrix from camera position and orientation (Euler Angles)
fixed** xform_world_to_camera_mat(vertex camera, fixed alpha_x, fixed beta_y, fixed gamma_z){

    fixed dummy_mat[4][4];

    // camera to world matrix
    fixed camera_to_world_stk[4][4] = {
        {fpm::cos(beta_y)*fpm::cos(gamma_z),  fpm::sin(alpha_x)*fpm::sin(beta_y)*fpm::cos(gamma_z) - fpm::cos(alpha_x)*fpm::sin(gamma_z),
        fpm::cos(alpha_x)*fpm::sin(beta_y)*fpm::cos(gamma_z) + fpm::sin(alpha_x)*fpm::sin(gamma_z), camera.x},

        {fpm::cos(beta_y)*fpm::sin(gamma_z),  fpm::sin(alpha_x)*fpm::sin(beta_y)*fpm::sin(gamma_z) + fpm::cos(alpha_x)*fpm::cos(gamma_z),
        fpm::cos(alpha_x)*fpm::sin(beta_y)*fpm::cos(gamma_z) - fpm::sin(alpha_x)*fpm::cos(gamma_z), camera.y},

        {-fpm::sin(beta_y), fpm::sin(alpha_x)*fpm::cos(beta_y), fpm::cos(alpha_x)*fpm::cos(beta_y), camera.z},

        {(F)0, (F)0, (F)0, (F)1}
    };

    fixed** camera_to_world = mat_stk_to_heap_4x4(camera_to_world_stk); // copy input matrix to heap
    fixed** world_to_camera = mat_stk_to_heap_4x4(dummy_mat); // allocate result matrix

    inv_mat_4x4(camera_to_world, world_to_camera); // invert camera_to_world

    mat_delete(camera_to_world, 4);

    return world_to_camera;

}


// generate a 35mm camera perspective projecton matrix
fixed** xform_projection_mat(){
    // setup camera sensor model & view frustrum
    fixed focalLength = (F)35; // 35mm Full Aperture
    fixed filmApertureWidth = (F)0.980; 
    fixed filmApertureHeight = (F)0.735; 
    fixed inchToMm = (F)25.4; 
    fixed nearClippingPlane = (F)0.1; 
    fixed farClipingPlane = (F)100; 

    zb_init((SF)farClipingPlane); // Z Buffer set to far clip plane

    // Second method. Compute the right and top coordinates directly
    fixed r = ((filmApertureWidth * inchToMm / 2) / focalLength) * nearClippingPlane; 
    fixed t = ((filmApertureHeight * inchToMm / 2) / focalLength) * nearClippingPlane;

    fixed n = nearClippingPlane;
    fixed f = farClipingPlane;
    fixed l = -r;
    fixed b = -t;

    fixed proj_mat_stk[4][4] = {
        {2*n/(r-l),      (F)0, (r+l)/(r-l)   ,         (F)0},
        {     (F)0, 2*n/(t-b), (t+b)/(t-b)   ,         (F)0},
        {     (F)0,      (F)0, -1*(f+n)/(f-n), -2*f*n/(f-n)},
        {     (F)0,      (F)0,          (F)-1,          (F)0}
    };
    fixed** proj_mat = mat_stk_to_heap_4x4(proj_mat_stk);
    return proj_mat;

}
