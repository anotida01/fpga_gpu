// cmodel_golden.cpp — minimal C-ABI stubs (Phase A item 3.1).
//
// This file exists only so cmodel_golden exports the 8 public symbols the
// Phase B DPI-C import will need. Each returns 0 ("OK") for now and will be
// filled in by Phase A items 3.2-3.9. The work order's item 3.1 acceptance is
// purely "nm -D | c++filt | grep cmodel_" — these stubs satisfy that.

#include "cmodel_golden.h"

cmodel_rc cmodel_init(int w, int h){
    (void)w; (void)h;
    return 0;
}

cmodel_rc cmodel_load_mesh(const char *memh_path){
    (void)memh_path;
    return 0;
}

cmodel_rc cmodel_render(void){
    return 0;
}

cmodel_rc cmodel_fb_pixel(int x, int y){
    (void)x; (void)y;
    return 0;
}

cmodel_rc cmodel_z_pixel(int x, int y){
    (void)x; (void)y;
    return 0;
}

cmodel_rc cmodel_reset(void){
    return 0;
}

cmodel_rc cmodel_selftest(void){
    return 0;
}

cmodel_rc cmodel_version(void){
    return 1;
}
