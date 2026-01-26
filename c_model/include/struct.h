
#ifndef __STRUCT_H__
#define __STRUCT_H__

#ifdef __cplusplus

    #include "fpm/fixed.hpp"
    #include "fpm/ios.hpp"
    #include "fpm/math.hpp"

    // using fixed = fpm::fixed_16_16;
    // using fixed = fpm::fixed_24_8;

    // Q13.14 on FPGA
    using fixed = fpm::fixed<std::int32_t, std::int64_t, 14>;
    using F = fixed; 
    
    using long_fixed = fpm::fixed<std::int32_t, std::int64_t, 14>;
    using LF = long_fixed;

    // used for Z-BUFFER
    // Q4.13 on FPGA
    using short_fixed = fpm::fixed<std::int32_t, std::int64_t, 13>;
    using SF = short_fixed;

#endif

typedef struct colour{
    fixed red;
    fixed green;
    fixed blue;
} colour;

typedef struct vertex {
    fixed x, y, z, w; // vertex position
    fixed xn, yn, zn; // vertex normal
    colour c;
} vertex;

typedef struct triangle {
    vertex p0, p1, p2;
} triangle;

void print_vertex(vertex* v);
void print_triangle(triangle* t);

#endif


