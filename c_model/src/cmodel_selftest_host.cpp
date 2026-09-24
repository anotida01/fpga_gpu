// cmodel_selftest_host.cpp - host driver for the C model self-test (the
// "golden of the golden", README §7.6).
//
// Links the same translation units as libcmodel_golden.so and calls
// cmodel_selftest() directly, so `make selftest` exercises exactly the
// code the shared library exports. Prints a PASS/FAIL line and returns
// 0 / non-zero (the self-test bitmask) so CI can gate on it.

#include <cstdio>
#include "cmodel_golden.h"

int main(void){
    unsigned int st = cmodel_selftest();
    if (st == 0){
        printf("CMODEL_SELFTEST: PASS (cmodel_selftest == 0, cmodel_version == %u)\n",
               cmodel_version());
        return 0;
    }
    printf("CMODEL_SELFTEST: FAIL (cmodel_selftest == %u: failed sub-checks %s%s%s%s%s%s%s%s%s%s%s%s)\n",
           st,
           (st & 1) ? "(a)exact-known-answers " : "",
           (st & 2) ? "(b)rounded-variant " : "",
           (st & 4) ? "(c)seeded-sweep " : "",
           (st & 8) ? "(d)write-load-roundtrip " : "",
           (st & 16) ? "6A(xform) " : "",
           (st & 32) ? "6B(w_norm) " : "",
           (st & 64) ? "6C(winding) " : "",
           (st & 128) ? "6D(edge) " : "",
           (st & 256) ? "6E(inv_z) " : "",
           (st & 512) ? "6F(depth) " : "",
           (st & 1024) ? "6G(raster) " : "",
           (st & 2048) ? "6H(sweeps) " : "");
    return st;
}
