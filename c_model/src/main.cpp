
// C Includes
#include <stdio.h>
#include <math.h>
#include <time.h>
#include <stdlib.h>

// C++ Includes
#include <string>
#include <vector>
#include <iostream>

// Local Includes
#include "main.h"
#include "renderer.h"
#include "struct.h"
#include "obj.h"
#include "matrix.h"
#include "transform.h"
#include "mif.h"
#include "cmodel_core.h"

#include "animate.h"

inline fixed to_rad(float degrees) {
    return (F)(degrees * (M_PI / 180.0));
}


// Find out which algorithm should be run
std::string parse_args(int argc, char** argv){
    std::string obj_path;
    if (argc == 2)
        obj_path = argv[1];
    else if (argc == 1){
        printf("Syntax is: %s <FILE_NAME>\n", argv[0]);
        exit(-1);
    }
    return obj_path;
}


// writes FRAMEBUFFER to OUTFILE and frees all memory allocations
void cleanup(){
    printf("OpenGL/GLUT exited. Cleaning Up Program\n");

    // // setup outfile array 
    // char** vga_colour_array = (char**) malloc(sizeof(char*) * V_SIZE);
    // for (size_t i = 0; i < V_SIZE; i++){
    //     vga_colour_array[i] = (char*) malloc(sizeof(char)*H_SIZE);
    // }

    // // convert FRAMEBUFFER to testbench format
    // __convert_fb_to_vga(vga_colour_array);

    // free all allocated memory
    for (size_t i = 0; i < V_SIZE; i++){
        free(FRAMEBUFFER[i]);
    }
    free(FRAMEBUFFER);
    return;
}


int main(int argc, char** argv){

    /************* Load in the object *************/

    // get .obj file
    std::string obj_path;
    obj_path = parse_args(argc, argv);

    OBJ = load_obj(obj_path);
    std::vector<triangle>* object = copy_obj(OBJ);

    std::cout << "Object Loaded from: " << obj_path << std::endl;
    printf("\tTriangles: %li\n\tMemory Usage %.3f kB\n", object->size(), (sizeof(triangle)*object->capacity()) / 1000.0);


    /************* Setup buffers *************/

    // F-Buffer
    int frame_buff_size = 0;
    FRAMEBUFFER = (colour**) malloc(sizeof(colour*) * V_SIZE);
    frame_buff_size += sizeof(colour*) * V_SIZE;
    for (size_t i = 0; i < V_SIZE; i++){
        FRAMEBUFFER[i] = (colour*) calloc(H_SIZE, sizeof(colour));
        frame_buff_size += sizeof(colour) * H_SIZE;
    }
    ren_fb_clear();
    printf("F-BUFFER is %d bytes\n", frame_buff_size);

    // Z-buffer
    int z_buff_size = 0;
    Z_BUFFER = (short_fixed**) malloc(sizeof(short_fixed*) * V_SIZE);
    z_buff_size += sizeof(short_fixed*) * V_SIZE;
    for (size_t i = 0; i < V_SIZE; i++){
        Z_BUFFER[i] = (short_fixed*) calloc(H_SIZE, sizeof(short_fixed));
        z_buff_size += sizeof(short_fixed) * H_SIZE;
    }
    printf("Z-BUFFER is %d bytes\n", z_buff_size);


    /************* Transform object from world to screen *************/

    /* scene currently described in world-space
       need to transform scene to camera space */

    // camera location & orientation
    vertex camera; camera.x=(F)7.3589; camera.y= (F)-6.9258; camera.z=(F)4.9583;
    fixed alpha_x = to_rad(64.3), beta_y = to_rad(0), gamma_z = to_rad(46.7);

    // camera transformation matrix
    WRLD_TO_CAM_MAT = xform_world_to_camera_mat(camera, alpha_x, beta_y, gamma_z);

    /* CLIPPING - would go here... */

    // projection matrix
    PROJ_MAT = xform_projection_mat();

    // composite transformation matrix
    fixed dummy_mat[4][4];
    COMP_XFORM_MAT = mat_stk_to_heap_4x4(dummy_mat);
    fixed** tmp_mat = mat_stk_to_heap_4x4(dummy_mat);
    mat_mul(PROJ_MAT, WRLD_TO_CAM_MAT, tmp_mat, 4);

    // transform object. enable w normalization
    // xform_obj(object, COMP_XFORM_MAT, 1);

    // scale object to screen space
    // scale_to_raster_obj(object);

    fixed c = (F)(0.5*H_SIZE); fixed d = (F)(0.5*V_SIZE);
    fixed scale_to_ras_stk[4][4] = {
        {c,     (F)0,   (F)0,      c},
        {(F)0,    -d,   (F)0,      d},
        {(F)0,  (F)0,   (F)1,   (F)0},
        {(F)0,  (F)0,   (F)0,   (F)1}
    };

    SCALE_TO_RAS_MAT = mat_stk_to_heap_4x4(scale_to_ras_stk);

    mat_mul(SCALE_TO_RAS_MAT, tmp_mat, COMP_XFORM_MAT, 4);

    xform_obj(object, COMP_XFORM_MAT, 1);

    // object is now in camera space & has proper projection & scaled to raster
    // save a copy of obj as it is now for simple light transformations
    RASTER_SPACE_OBJ = copy_obj(object);

    /************* Shade & draw object *************/

    // light initially in same place as camera
    LIGHT.x=camera.x; LIGHT.y=camera.y; LIGHT.z=camera.z;

    // normalize to unit vector
    fixed light_mag = sqrt(pow(LIGHT.x, 2) + pow(LIGHT.y, 2) + pow(LIGHT.z, 2));
    LIGHT.x /= light_mag; LIGHT.y /= light_mag; LIGHT.z /= light_mag;

    shade_obj(object, &LIGHT);
    draw_obj(object);
    printf("TRI: %d CCW: %d\n", TRI, CCW);
    
    std::string mif_path = "../out_mif.memh";
    generate_obj_memh(OBJ, mif_path);

    mif_path = "../raster.memh";
    generate_obj_memh(RASTER_SPACE_OBJ, mif_path);

    // delete local copy of object
    delete object;

    // register cleanup() to be called when exiting
    atexit(cleanup);

    start_renderer(argc, argv);

    return 0;
}
