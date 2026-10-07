/* rvv_vadd.c — Integer vector add test for qemu-riscv64 (rv64imafdcv)
 *
 * Same algorithm as rvv_vadd_smoke.s (RTL side) — for direct comparison.
 *
 * A = {1,2,3,4,5,6,7,8}
 * B = {10,20,30,40,50,60,70,80}
 * Expected C = {11,22,33,44,55,66,77,88}
 */

#include <stdint.h>
#include <stddef.h>
#include <stdio.h>
#include <riscv_vector.h>

#define N 8

static const int32_t arr_a[N]   = {1,  2,  3,  4,  5,  6,  7,  8};
static const int32_t arr_b[N]   = {10, 20, 30, 40, 50, 60, 70, 80};
static const int32_t arr_exp[N] = {11, 22, 33, 44, 55, 66, 77, 88};

int main(void) {
    int32_t arr_c[N];

    printf("=== RVV VADD TEST (rv64v/qemu) ===\n");

    /* vsetvl loop — handles any VLEN (VLMAX may be < N) */
    for (int i = 0; i < N; ) {
        size_t vl = __riscv_vsetvl_e32m1(N - i);

        vint32m1_t v0 = __riscv_vle32_v_i32m1(arr_a + i, vl);
        vint32m1_t v1 = __riscv_vle32_v_i32m1(arr_b + i, vl);
        vint32m1_t v2 = __riscv_vadd_vv_i32m1(v0, v1, vl);
        __riscv_vse32_v_i32m1(arr_c + i, v2, vl);

        i += (int)vl;
    }

    /* print and verify */
    printf(" i |  A |  B |  C | EXP | CHK\n");
    printf("---+----+----+----+-----+----\n");

    int all_pass = 1;
    for (int i = 0; i < N; i++) {
        int ok = (arr_c[i] == arr_exp[i]);
        all_pass &= ok;
        printf(" %d | %2d | %2d | %2d |  %2d | %s\n",
               i,
               arr_a[i], arr_b[i], arr_c[i], arr_exp[i],
               ok ? "OK" : "FAIL");
    }

    printf("RESULT: %s\n", all_pass ? "PASS" : "FAIL");
    return all_pass ? 0 : 1;
}
