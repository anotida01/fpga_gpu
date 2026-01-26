
#include <stdio.h>
#include "struct.h"

void print_vertex(vertex* v){

    printf("\tVertex:\t< %6.3f %6.3f %6.3f %6.3f >\n", v->x, v->y, v->z, v->w);
    printf("\t\tNormal:\t< %6.3f %6.3f %6.3f >\n", v->xn, v->yn, v->zn);
    printf("\t\tColour:\t< r:%6.3f g:%6.3f b:%6.3f >\n\n", v->c.red, v->c.green, v->c.blue);

}

void print_triangle(triangle* t){
    
    print_vertex(&(t->p0));
    print_vertex(&(t->p1));
    print_vertex(&(t->p2));

}
