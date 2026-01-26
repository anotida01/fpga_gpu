#include <stdio.h>
#include <stdlib.h>
#include "matrix.h"
#include "struct.h"


fixed** mat_stk_to_heap_4x4(fixed matrix[][4]){

    fixed** heap_matrix = (fixed**) malloc(sizeof(fixed*) * 4);
    for (size_t i = 0; i < 4; i++){
        heap_matrix[i] = (fixed*) malloc(sizeof(fixed*) * 4);
        for (size_t j = 0; j < 4; j++)
            heap_matrix[i][j] = matrix[i][j];
    }

    return heap_matrix;

}

fixed** mat_stk_to_heap_3x3(fixed matrix[][3]){

    fixed** heap_matrix = (fixed**) malloc(sizeof(fixed*) * 3);
    for (size_t i = 0; i < 3; i++){
        heap_matrix[i] = (fixed*) malloc(sizeof(fixed*) * 3);
        for (size_t j = 0; j < 3; j++)
            heap_matrix[i][j] = matrix[i][j];
    }

    return heap_matrix;

}

fixed** mat_stk_to_heap_2x2(fixed matrix[][2]){

    fixed** heap_matrix = (fixed**) malloc(sizeof(fixed*) * 2);
    for (size_t i = 0; i < 2; i++){
        heap_matrix[i] = (fixed*) malloc(sizeof(fixed*) * 2);
        for (size_t j = 0; j < 2; j++)
            heap_matrix[i][j] = matrix[i][j];
    }

    return heap_matrix;

}

void mat_vec_mul(fixed** matrix, fixed* vector, fixed* result, int n){

    for (int i = 0; i < n; i++)
        result[i] = (F)0;

    for (int i = 0; i < n; i++){
        for (int j = 0; j < n; j++)
            result[j] += matrix[j][i] * vector[i];
    }

}

void mat_mul(fixed** a, fixed** b, fixed** result, int n){

    int i, j, k;
    for (i = 0; i < n; i++){
        for (j = 0; j < n; j++){
                result[i][j] = (F)0;
                for (k = 0; k < n; k++){

                result[i][j] += a[i][k] * b[k][j];

            }
        }

    }

}

void print_matrix_heap(fixed** matrix, int n){

    for (int i = 0; i < n; i++)
    {
        printf("[ ");
        for (int j = 0; j < n; j++)
        {
            printf("%7.3f ", matrix[i][j]);
        }
        printf("  ]\n");
        
    }

    return;

}

void print_vector(fixed* vector, int n){

    printf("< ");
    for (int i = 0; i < n; i++)
        printf("%.3f ", vector[i]);
    printf(">\n");    

}

bool inv_mat_4x4(fixed** A, fixed** B){

  B[0][0] = A[1][2]*A[2][3]*A[3][1] - A[1][3]*A[2][2]*A[3][1] + A[1][3]*A[2][1]*A[3][2] - A[1][1]*A[2][3]*A[3][2] - A[1][2]*A[2][1]*A[3][3] + A[1][1]*A[2][2]*A[3][3];
  B[0][1] = A[0][3]*A[2][2]*A[3][1] - A[0][2]*A[2][3]*A[3][1] - A[0][3]*A[2][1]*A[3][2] + A[0][1]*A[2][3]*A[3][2] + A[0][2]*A[2][1]*A[3][3] - A[0][1]*A[2][2]*A[3][3];
  B[0][2] = A[0][2]*A[1][3]*A[3][1] - A[0][3]*A[1][2]*A[3][1] + A[0][3]*A[1][1]*A[3][2] - A[0][1]*A[1][3]*A[3][2] - A[0][2]*A[1][1]*A[3][3] + A[0][1]*A[1][2]*A[3][3];
  B[0][3] = A[0][3]*A[1][2]*A[2][1] - A[0][2]*A[1][3]*A[2][1] - A[0][3]*A[1][1]*A[2][2] + A[0][1]*A[1][3]*A[2][2] + A[0][2]*A[1][1]*A[2][3] - A[0][1]*A[1][2]*A[2][3];
  B[1][0] = A[1][3]*A[2][2]*A[3][0] - A[1][2]*A[2][3]*A[3][0] - A[1][3]*A[2][0]*A[3][2] + A[1][0]*A[2][3]*A[3][2] + A[1][2]*A[2][0]*A[3][3] - A[1][0]*A[2][2]*A[3][3];
  B[1][1] = A[0][2]*A[2][3]*A[3][0] - A[0][3]*A[2][2]*A[3][0] + A[0][3]*A[2][0]*A[3][2] - A[0][0]*A[2][3]*A[3][2] - A[0][2]*A[2][0]*A[3][3] + A[0][0]*A[2][2]*A[3][3];
  B[1][2] = A[0][3]*A[1][2]*A[3][0] - A[0][2]*A[1][3]*A[3][0] - A[0][3]*A[1][0]*A[3][2] + A[0][0]*A[1][3]*A[3][2] + A[0][2]*A[1][0]*A[3][3] - A[0][0]*A[1][2]*A[3][3];
  B[1][3] = A[0][2]*A[1][3]*A[2][0] - A[0][3]*A[1][2]*A[2][0] + A[0][3]*A[1][0]*A[2][2] - A[0][0]*A[1][3]*A[2][2] - A[0][2]*A[1][0]*A[2][3] + A[0][0]*A[1][2]*A[2][3];
  B[2][0] = A[1][1]*A[2][3]*A[3][0] - A[1][3]*A[2][1]*A[3][0] + A[1][3]*A[2][0]*A[3][1] - A[1][0]*A[2][3]*A[3][1] - A[1][1]*A[2][0]*A[3][3] + A[1][0]*A[2][1]*A[3][3];
  B[2][1] = A[0][3]*A[2][1]*A[3][0] - A[0][1]*A[2][3]*A[3][0] - A[0][3]*A[2][0]*A[3][1] + A[0][0]*A[2][3]*A[3][1] + A[0][1]*A[2][0]*A[3][3] - A[0][0]*A[2][1]*A[3][3];
  B[2][2] = A[0][1]*A[1][3]*A[3][0] - A[0][3]*A[1][1]*A[3][0] + A[0][3]*A[1][0]*A[3][1] - A[0][0]*A[1][3]*A[3][1] - A[0][1]*A[1][0]*A[3][3] + A[0][0]*A[1][1]*A[3][3];
  B[2][3] = A[0][3]*A[1][1]*A[2][0] - A[0][1]*A[1][3]*A[2][0] - A[0][3]*A[1][0]*A[2][1] + A[0][0]*A[1][3]*A[2][1] + A[0][1]*A[1][0]*A[2][3] - A[0][0]*A[1][1]*A[2][3];
  B[3][0] = A[1][2]*A[2][1]*A[3][0] - A[1][1]*A[2][2]*A[3][0] - A[1][2]*A[2][0]*A[3][1] + A[1][0]*A[2][2]*A[3][1] + A[1][1]*A[2][0]*A[3][2] - A[1][0]*A[2][1]*A[3][2];
  B[3][1] = A[0][1]*A[2][2]*A[3][0] - A[0][2]*A[2][1]*A[3][0] + A[0][2]*A[2][0]*A[3][1] - A[0][0]*A[2][2]*A[3][1] - A[0][1]*A[2][0]*A[3][2] + A[0][0]*A[2][1]*A[3][2];
  B[3][2] = A[0][2]*A[1][1]*A[3][0] - A[0][1]*A[1][2]*A[3][0] - A[0][2]*A[1][0]*A[3][1] + A[0][0]*A[1][2]*A[3][1] + A[0][1]*A[1][0]*A[3][2] - A[0][0]*A[1][1]*A[3][2];
  B[3][3] = A[0][1]*A[1][2]*A[2][0] - A[0][2]*A[1][1]*A[2][0] + A[0][2]*A[1][0]*A[2][1] - A[0][0]*A[1][2]*A[2][1] - A[0][1]*A[1][0]*A[2][2] + A[0][0]*A[1][1]*A[2][2];

    return true;

}

void mat_delete(fixed** matrix, unsigned int n){
    for (size_t i = 0; i < n; i++)
        free(matrix[i]);

    free(matrix);
    
    return;
}

// void test_mat_mul(){
//     fixed a_stk[4][4] = {
//         {1, 2, 3, 4},
//         {1, 2, 3, 4}, 
//         {5, 6, 7, 8}, 
//         {5, 6, 7, 8}
//     };

//     fixed b_stk[4][4] = {
//         {1, 2, 3, 4},
//         {1, 2, 3, 4}, 
//         {5, 6, 7, 8}, 
//         {5, 6, 7, 8}
//     };

//     fixed** a = mat_stk_to_heap_4x4(a_stk);
//     fixed** b = mat_stk_to_heap_4x4(b_stk);
//     fixed** result = mat_stk_to_heap_4x4(b_stk);

//     mat_mul(a, b, result, 4);

//     print_matrix_heap(result, 4);
// }