#include <stdio.h>
#include <stdlib.h>

#include <iostream>
#include <fstream>
#include <vector>

#include "mif.h"
#include "struct.h"
#include "main.h"

void write_out_vertex(vertex v, std::ofstream* o_file, int w, int normal){
    char buf[BUFSIZ];
    if (w)
        sprintf(buf, "%08x\n%08x\n%08x\n%08x\n", v.x, v.y, v.z, v.w);
    else 
        sprintf(buf, "%08x\n%08x\n%08x\n", v.x, v.y, v.z);

    *o_file << buf;
    if (normal){
        sprintf(buf, "%08x\n%08x\n%08x\n", v.xn, v.yn, v.zn);
        *o_file << buf;
    }
}

void generate_obj_memh(std::vector<triangle>* object, std::string o_file_path){

    std::ofstream o_file;
    char buf[BUFSIZ];

    o_file.open(o_file_path.c_str(), std::ios::trunc);

    if (o_file.is_open()){

        // First 16 Words are the composite matrix multiply coeffs
        for (size_t i = 0; i < 4; i++)
            for (size_t j = 0; j < 4; j++){

                sprintf(buf, "%08x\n", COMP_XFORM_MAT[i][j]);
                o_file << buf;

            }

        // Next 3 Words are the light vertex

        write_out_vertex(LIGHT, &o_file, 0, 0);

        // Next word is the number of vertices (IN REGULAR BINARY)
        sprintf(buf, "%08x\n", object->size() * 3 * 7);
        o_file << buf;

        // the remaining words are the object vertices and normals

        for (size_t i = 0; i < object->size(); i++)
        {
            triangle t = object->at(i);

            write_out_vertex(t.p0, &o_file, 1, 1);
            write_out_vertex(t.p1, &o_file, 1, 1);
            write_out_vertex(t.p2, &o_file, 1, 1);
            
        }

    } else {
        std::cerr << "ERROR: Could not open " << o_file_path << std::endl;
        return;
    }




}


