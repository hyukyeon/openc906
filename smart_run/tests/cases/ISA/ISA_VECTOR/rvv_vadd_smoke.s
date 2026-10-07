/* rvv_vadd_smoke.s — Integer vector add smoke test for C906 RTL (iverilog)
 *
 * Algorithm : C[i] = A[i] + B[i]  (i = 0..7, int32)
 * A = {1,2,3,4,5,6,7,8}
 * B = {10,20,30,40,50,60,70,80}
 * Expected  = {11,22,33,44,55,66,77,88}
 *
 * Encoding note:
 *   vsetvli rd, rs1, e32, m1, tu, mu  →  vtypei = 0x02
 *   In RVV 0.7.x (C906), bits[7:6] of vtypei are reserved=0
 *   tu/mu maps exactly to those bits=0 → binary compatible.
 *
 * Pass/fail signalling (tb.v):
 *   __exit : loads 0x444333222 into x3  → TEST PASS
 *   __fail : loads 0x2382348720 into x3 → TEST FAIL
 *
 * UART output:
 *   sw to 0x10015000 — testbench intercepts and prints wdata[7:0]
 */

.text
.align 2
.global main

/* ------------------------------------------------------------------
 * uart_puts(a0 = char*) — write null-terminated string via UART
 * ------------------------------------------------------------------ */
uart_puts:
    li      t0, 0x10015000
1:  lb      t1, 0(a0)
    beqz    t1, 2f
    sw      t1, 0(t0)
    addi    a0, a0, 1
    j       1b
2:  ret

/* ------------------------------------------------------------------
 * main
 * ------------------------------------------------------------------ */
main:
    la      a0, str_header
    call    uart_puts

    /* vsetvli C906 RVV 0.7.x encoding: vtypei layout differs from RVV 1.0
     *   RVV 1.0 : bits[5:3]=vsew, bits[2:0]=vlmul  → e32,m1 = vtypei=0x10
     *   RVV 0.7x: bits[2:0]=vsew, bits[4:3]=vlmul  → e32,m1 = vtypei=0x02
     * Encode directly as .word to guarantee correct C906 binary.
     *   vsetvli t1, t0, <vtypei=2>
     *   = vtypei[11:0]=0x002 | rs1=t0(5) | funct3=111 | rd=t1(6) | op=1010111
     *   = 0x0022F357                                                          */
    li      t0, 8
    .word   0x0022F357       /* vsetvli t1, t0, e32  (C906 v0.7.x) */

    /* load A and B */
    la      a0, arr_a
    la      a1, arr_b
    vle32.v v0, (a0)        /* v0 = A */
    vle32.v v1, (a1)        /* v1 = B */

    /* C = A + B */
    vadd.vv v2, v0, v1

    /* store result */
    la      a2, arr_c
    vse32.v v2, (a2)

    /* verify arr_c == arr_exp, element by element */
    la      a3, arr_c
    la      a4, arr_exp
    li      t2, 8

verify_loop:
    beqz    t2, verify_pass
    lw      t3, 0(a3)
    lw      t4, 0(a4)
    bne     t3, t4, verify_fail
    addi    a3, a3, 4
    addi    a4, a4, 4
    addi    t2, t2, -1
    j       verify_loop

verify_pass:
    la      a0, str_pass
    call    uart_puts
    j       __exit          /* → TEST PASS in run_case.report */

verify_fail:
    la      a0, str_fail
    call    uart_puts
    j       __fail          /* → TEST FAIL in run_case.report */

/* ------------------------------------------------------------------ */
.section .rodata
str_header: .asciz "=== RVV VADD TEST (rv64v/rtl) ===\n"
str_pass:   .asciz "RESULT: PASS\n"
str_fail:   .asciz "RESULT: FAIL\n"

.data
.align 4
arr_a:   .word  1,  2,  3,  4,  5,  6,  7,  8
arr_b:   .word 10, 20, 30, 40, 50, 60, 70, 80
arr_c:   .word  0,  0,  0,  0,  0,  0,  0,  0
arr_exp: .word 11, 22, 33, 44, 55, 66, 77, 88
