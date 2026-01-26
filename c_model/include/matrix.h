#ifndef __MATRIX_H__
#define __MATRIX_H__

#include "struct.h"

fixed** mat_stk_to_heap_4x4(fixed matrix[][4]);
fixed** mat_stk_to_heap_3x3(fixed matrix[][3]);
fixed** mat_stk_to_heap_2x2(fixed matrix[][2]);
void mat_vec_mul(fixed** matrix, fixed* vector, fixed* result, int n);
void print_matrix_heap(fixed** matrix, int n);
void print_vector(fixed* vector, int n);
void mat_mul(fixed** a, fixed** b, fixed** result, int n);

bool inv_mat_4x4(fixed** A, fixed** B);
void mat_delete(fixed** matrix, unsigned int n);

#endif
