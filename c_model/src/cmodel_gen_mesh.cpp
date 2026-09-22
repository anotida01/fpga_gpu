// cmodel_gen_mesh.cpp — test mesh emitter for the vn_shade unit-level flow.
//
// Emits a .memh mesh file in the 16+3+1+N*7 format (8-hex-digit lines,
// two's-complement Q13.14 raw values) that cmodel_load_mesh accepts.
// Intended for per-vertex directed tests (tc_vn_shade_per_vertex): every
// vertex carries a distinct, known normal so each DUT vn_o word can be
// checked against its own exact dot product.
//
// Modes:
//   --mode directed (default):
//       positions cycle the 8 unit-box corners (±16384), w = 16384;
//       normals cycle 8 directed vectors: the 6 axis units (±16384) plus
//       the multi-component (8192,8192,8192) and (-8192,0,8192).
//   --mode random:
//       every position/normal component is seed-uniform in [-16384,16384];
//       w = 16384.
//
// Range contract:
//   * normals and light: kept inside the 27-bit DUT port range
//     (|v| < 2^26) in both modes, so every emitted normal is a valid vn_in
//     word;
//   * positions: may use the full 32-bit range (the v_xform port is wider
//     than vn_in); this emitter bounds every position component to
//     [-16384,16384] and w to 16384 in both modes (documented in --help).
//
// Deterministic: the RNG is a 32-bit LCG (Numerical Recipes constants),
// so a given --seed reproduces the same mesh on every platform.

#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <cstdint>
#include "cmodel_golden.h"

static const int BOX_LIGHT[3] = { 10711, -10081, 7217 };

// 8 directed normals: 6 axis units + 2 multi-component.
static const int DIRECTED_NRM[8][3] = {
    { -16384,      0,      0 },
    {  16384,      0,      0 },
    {      0, -16384,      0 },
    {      0,  16384,      0 },
    {      0,      0, -16384 },
    {      0,      0,  16384 },
    {   8192,   8192,   8192 },
    {  -8192,      0,   8192 },
};

// 8 unit-box corners (±16384).
static const int BOX_CORNER[8][3] = {
    { -16384, -16384, -16384 },
    {  16384, -16384, -16384 },
    { -16384,  16384, -16384 },
    {  16384,  16384, -16384 },
    { -16384, -16384,  16384 },
    {  16384, -16384,  16384 },
    { -16384,  16384,  16384 },
    {  16384,  16384,  16384 },
};

static uint32_t g_rng = 0;

// Seed-uniform in [-16384, 16384] (32769 values; modulo bias negligible
// for test stimulus).
static int rand_bounded(void){
    g_rng = g_rng * 1664525u + 1013904223u;
    return (int)(g_rng % 32769u) - 16384;
}

static void usage(const char *argv0){
    fprintf(stderr,
        "usage: %s --out PATH [--mode directed|random] [--seed N]\n"
        "                  [--verts N] [--light LX,LY,LZ] [--matrix PATH]\n"
        "\n"
        "Options:\n"
        "  --out PATH      output .memh path (required)\n"
        "  --mode M        directed (default) or random\n"
        "  --seed N        RNG seed for random mode (default 12345);\n"
        "                  deterministic per seed (32-bit LCG)\n"
        "  --verts N       vertex count (positive multiple of 3, default 36)\n"
        "  --light L       light as LX,LY,LZ signed decimal (default box\n"
        "                  light 10711,-10081,7217); 27-bit range required\n"
        "  --matrix PATH   16-word file (8-hex lines) for the transform\n"
        "                  matrix; default: Q13.14 4x4 identity\n"
        "\n"
        "Format: 16+3+1+N*7 words, 8-hex-digit lines, two's-complement raw\n"
        "values; each vertex = (x,y,z,w,nx,ny,nz). Round-trips with\n"
        "cmodel_load_mesh.\n"
        "\n"
        "Range contract: emitted normals and light stay inside the 27-bit\n"
        "DUT port range (|v| < 2^26, the vn_in port width); positions may\n"
        "use the full 32-bit range (the v_xform port is wider) — this\n"
        "emitter bounds every position component to [-16384,16384] and\n"
        "w to 16384 in both modes so meshes stay well-formed for\n"
        "downstream transform stages.\n");
}

int main(int argc, char **argv){
    const char *out = NULL;
    const char *matrix_path = NULL;
    int mode_random = 0;
    int seed = 12345;
    int nverts = 36;
    int light[3] = { BOX_LIGHT[0], BOX_LIGHT[1], BOX_LIGHT[2] };

    for (int i = 1; i < argc; i++){
        if (!strcmp(argv[i], "--out") && i + 1 < argc){
            out = argv[++i];
        } else if (!strcmp(argv[i], "--mode") && i + 1 < argc){
            i++;
            if (!strcmp(argv[i], "random")) mode_random = 1;
            else if (!strcmp(argv[i], "directed")) mode_random = 0;
            else { usage(argv[0]); return 1; }
        } else if (!strcmp(argv[i], "--seed") && i + 1 < argc){
            seed = atoi(argv[++i]);
        } else if (!strcmp(argv[i], "--verts") && i + 1 < argc){
            nverts = atoi(argv[++i]);
        } else if (!strcmp(argv[i], "--light") && i + 1 < argc){
            if (sscanf(argv[++i], "%d,%d,%d", &light[0], &light[1], &light[2]) != 3){
                usage(argv[0]);
                return 1;
            }
        } else if (!strcmp(argv[i], "--matrix") && i + 1 < argc){
            matrix_path = argv[++i];
        } else if (!strcmp(argv[i], "-h") || !strcmp(argv[i], "--help")){
            usage(argv[0]);
            return 0;
        } else {
            usage(argv[0]);
            return 1;
        }
    }

    if (!out){
        usage(argv[0]);
        return 1;
    }
    if (nverts <= 0 || nverts % 3 != 0){
        fprintf(stderr, "error: --verts must be a positive multiple of 3 (got %d)\n", nverts);
        return 1;
    }
    for (int i = 0; i < 3; i++){
        if (light[i] <= -0x4000000 || light[i] >= 0x4000000){
            fprintf(stderr, "error: light component %d outside the 27-bit range\n", light[i]);
            return 1;
        }
    }

    int mat[16];
    for (int i = 0; i < 16; i++)
        mat[i] = (i % 5 == 0) ? 16384 : 0;   // Q13.14 4x4 identity
    if (matrix_path){
        FILE *fp = fopen(matrix_path, "r");
        if (!fp){
            fprintf(stderr, "error: cannot open --matrix file %s\n", matrix_path);
            return 1;
        }
        unsigned int w;
        int n = 0;
        while (n < 16 && fscanf(fp, "%x", &w) == 1)
            mat[n++] = (int)(int32_t)w;
        fclose(fp);
        if (n != 16){
            fprintf(stderr, "error: --matrix file must contain 16 words (got %d)\n", n);
            return 1;
        }
    }

    int *verts = (int *)malloc(sizeof(int) * (size_t)nverts * 7);
    if (!verts){
        fprintf(stderr, "error: malloc failed\n");
        return 1;
    }

    g_rng = (uint32_t)seed;
    for (int v = 0; v < nverts; v++){
        int base = v * 7;
        if (mode_random){
            verts[base + 0] = rand_bounded();
            verts[base + 1] = rand_bounded();
            verts[base + 2] = rand_bounded();
            verts[base + 4] = rand_bounded();
            verts[base + 5] = rand_bounded();
            verts[base + 6] = rand_bounded();
        } else {
            const int *p = BOX_CORNER[v % 8];
            const int *n = DIRECTED_NRM[v % 8];
            verts[base + 0] = p[0];
            verts[base + 1] = p[1];
            verts[base + 2] = p[2];
            verts[base + 4] = n[0];
            verts[base + 5] = n[1];
            verts[base + 6] = n[2];
        }
        verts[base + 3] = 16384;   // w = 1.0 in both modes
    }

    cmodel_rc rc = cmodel_write_mesh(out, mat, light, verts, nverts);
    free(verts);
    if (rc != CMODEL_OK){
        fprintf(stderr, "error: cmodel_write_mesh(%s) failed\n", out);
        return 1;
    }
    if (mode_random)
        printf("wrote %s: %d vertices, mode=random seed=%d, light=(%d,%d,%d)\n",
               out, nverts, seed, light[0], light[1], light[2]);
    else
        printf("wrote %s: %d vertices, mode=directed, light=(%d,%d,%d)\n",
               out, nverts, light[0], light[1], light[2]);
    return 0;
}
