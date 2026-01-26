
#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>
#include <iostream>
#include <fstream>
#include <string>
#include <vector>
#include <sstream>

#include "struct.h"
#include "obj.h"
#include "main.h"
#include "renderer.h"
#include "algorithms.h"

typedef struct norm{
    fixed xn, yn, zn;
} norm;

long PIXEL_COUNT;

fixed dot_3(vertex a, vertex b){
    return a.xn * b.x + a.yn * b.y + a.zn * b.z;
}


void shade_obj(std::vector<triangle>* triangles, vertex* light){

    triangle t;
    fixed dot;

    for (size_t i = 0; i < triangles->size(); i++){ 
        
        t = triangles->at(i);

        // printf("Before Shading\n\n");
        // print_vertex(&t.p0);
        // print_vertex(&t.p1);
        // print_vertex(&t.p2);

        dot = dot_3( t.p0, *light );
        t.p0.c.red  = dot;
        t.p0.c.green = dot;
        t.p0.c.blue = dot;

        // printf("%08x\n", dot);

        dot = dot_3( t.p1, *light );
        t.p1.c.red = dot;
        t.p1.c.green = dot;
        t.p1.c.blue = dot;

        // printf("%08x\n", dot);

        dot = dot_3( t.p2, *light );
        t.p2.c.red = dot;
        t.p2.c.green = dot;
        t.p2.c.blue = dot;

        // printf("%08x\n", dot);


        // printf("After Shading\n\n");
        // print_vertex(&t.p0);
        // print_vertex(&t.p1);
        // print_vertex(&t.p2);

        triangles->at(i) = t;

    }

}


void draw_obj(std::vector<triangle>* triangles){

    for (size_t i = 0; i < triangles->size(); i++){
        draw_triangle( &(triangles->at(i)) );
    }

    // printf("Pixels Drawn: %d\n", PIXEL_COUNT);

}


void print_triangles(std::vector<triangle>* triangles){

    for (size_t i = 0; i < triangles->size(); i++)
    {
        printf("Triangle %li:\n", i);
        print_triangle( &(triangles->at(i)) );
        printf("\n");
    }

}


// deprecated no longer in use
void scale_to_raster_obj(std::vector<triangle>* triangles){

    // triangle t;

    // for (size_t i = 0; i < triangles->size(); i++){
    //     t = triangles->at(i);
    //     t.p0.x = (t.p0.x + 1) * 0.5 * H_SIZE;
    //     t.p0.y = 0.5*V_SIZE * (1 - t.p0.y);
    //     t.p1.x = (t.p1.x + 1) * 0.5 * H_SIZE;
    //     t.p1.y = 0.5*V_SIZE * (1 - t.p1.y);
    //     t.p2.x = (t.p2.x + 1) * 0.5 * H_SIZE;
    //     t.p2.y = 0.5*V_SIZE * (1 - t.p2.y);
    //     triangles->at(i) = t;

    //     // t.p0.y = ( 1 - (t.p0.y + 1) * 0.5) * V_SIZE;
    //     // t.p1.y = ( 1 - (t.p1.y + 1) * 0.5) * V_SIZE;
    //     // t.p2.y = ( 1 - (t.p2.y + 1) * 0.5) * V_SIZE;

    // }


}


std::vector<triangle>* copy_obj(std::vector<triangle>* obj_orig){

    std::vector<triangle>* copy = new std::vector<triangle>;

    for (size_t i = 0; i < obj_orig->size(); i++){
        copy->push_back(obj_orig->at(i));
    }

    return copy;

}


std::vector<triangle>* load_obj(std::string obj_path){
    
    PIXEL_COUNT = 0; // debug 

    std::ifstream obj_file;
    std::string line;
    std::string prefix;

    obj_file.open(obj_path.c_str());

    // vertice array
    std::vector<vertex>* v = new std::vector<vertex>;
    vertex v_tmp;
    v_tmp.w = (F)1;
    v_tmp.c.red=(F)1; v_tmp.c.green=(F)1; v_tmp.c.blue=(F)1;

    // vertice normal array
    std::vector<norm> vn;
    norm vn_tmp;

    // main triangle array
    std::vector<triangle>* t = new std::vector<triangle>;
    triangle t_tmp;
    int num_triangles = 0;

    std::stringstream ss;

    if (obj_file.is_open())
        while(std::getline(obj_file, line)){

            //Get the prefix of the line
            ss.clear();
            ss.str(line);
            ss >> prefix;

            if (prefix == "v") {

                ss >> v_tmp.x >> v_tmp.y >> v_tmp.z;
                v->push_back(v_tmp);

            }
            else if (prefix == "vn"){
                
                ss >> vn_tmp.xn >> vn_tmp.yn >> vn_tmp.zn;
                vn.push_back(vn_tmp);

            }
            else if (prefix == "f"){

                num_triangles++;

                // temporary variables
                vertex v1, v2, v3;
                unsigned int tmp;

                int counter = 0;

                while (ss >> tmp){
                    
                    if (counter == 0) v1 = v->at(tmp-1);
                    if (counter == 1) {
                        v1.xn = vn.at(tmp-1).xn;
                        v1.yn = vn.at(tmp-1).yn;
                        v1.zn = vn.at(tmp-1).zn;
                    }
                    if (counter == 2) v2 = v->at(tmp-1);
                    if (counter == 3) {
                        v2.xn = vn.at(tmp-1).xn;
                        v2.yn = vn.at(tmp-1).yn;
                        v2.zn = vn.at(tmp-1).zn;
                    }
                    if (counter == 4) v3 = v->at(tmp-1);
                    if (counter == 5) {
                        v3.xn = vn.at(tmp-1).xn;
                        v3.yn = vn.at(tmp-1).yn;
                        v3.zn = vn.at(tmp-1).zn;
                    }

                    counter++;

                    if (ss.peek() == '/') ss.ignore(2);

                }

                t_tmp.p0 = v1;
                t_tmp.p1 = v2;
                t_tmp.p2 = v3;

                t->push_back(t_tmp);

            }

        }
    else{
        std::cout << "ERROR: Could not open File\n";
        exit(-1);
    }

    obj_file.close();

    delete v;
    return t;
}
