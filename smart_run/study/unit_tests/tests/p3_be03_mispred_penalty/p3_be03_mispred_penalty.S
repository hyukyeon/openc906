# ============================================================================
# p3_be03_mispred_penalty : 분기 예측 실패 비용(penalty) 실측
#
#  같은 루프(256 회)에서 분기 조건만 바꾼다.
#    MARK 1 : 예측 가능한 분기 (항상 not-taken)
#    MARK 2 : 예측 불가능한 분기 (xorshift 난수의 bit0)
#  penalty = (사이클 차이) / (mispredict 수 차이)  -> 문서에서 계산
#
#  루프 본문은 두 경우 모두 동일한 명령 수(분기 taken 시 건너뛰는 1 명령 포함 여부만 다름).
# GTKW: fe bht id ex rt
# ============================================================================
#include "study.h"

#define N_ITER 256

  .text
  .option norvc
  .globl main
main:
  SET_MHCR(MHCR_DEFAULT)

  # ------------------------------------------------ MARK 1 : predictable
  INV_BP
  li   s7, 0                     # 난수 상태 0 -> 계속 0 -> bnez 항상 not-taken
  jal  ra, loop_const            # warm
  MARK(1)
  jal  ra, loop_const
  MARK(0)
  REPORT "const_cycles", s0
  REPORT "const_mispred", s1

  # ------------------------------------------------ MARK 2 : random
  INV_BP
  li   s7, 0x9E3779B97F4A7C15    # xorshift seed
  jal  ra, loop_rand             # warm
  MARK(2)
  jal  ra, loop_rand
  MARK(0)
  REPORT "rand_cycles", s0
  REPORT "rand_mispred", s1
  REPORT "rand_taken", s4
  j    pass

# ----------------------------------------------------------------------------
# 두 루프 모두: xorshift 갱신(6 명령) + andi + 조건분기 + (skip 대상 1 명령) + 카운터 2 명령
# ----------------------------------------------------------------------------
  .balign 64
loop_const:
  li   s2, N_ITER
  li   s4, 0
  csrr s3, mhpmcounter3
  TIC(s0)
1:
  slli t1, s7, 13
  xor  s7, s7, t1
  srli t1, s7, 7
  xor  s7, s7, t1
  slli t1, s7, 17
  xor  s7, s7, t1                # s7 = 0 으로 시작했으므로 계속 0
  andi t2, s7, 1
  bnez t2, 2f                    # 항상 not-taken
  addi s4, s4, 1
2:
  addi s2, s2, -1
  bnez s2, 1b
  TOC(s0)
  csrr s1, mhpmcounter3
  sub  s1, s1, s3
  ret

  .balign 64
loop_rand:
  li   s2, N_ITER
  li   s4, 0
  csrr s3, mhpmcounter3
  TIC(s0)
1:
  slli t1, s7, 13
  xor  s7, s7, t1
  srli t1, s7, 7
  xor  s7, s7, t1
  slli t1, s7, 17
  xor  s7, s7, t1
  andi t2, s7, 1
  bnez t2, 2f                    # 50% 확률로 taken (예측 불가)
  addi s4, s4, 1                 # not-taken 횟수
2:
  addi s2, s2, -1
  bnez s2, 1b
  TOC(s0)
  csrr s1, mhpmcounter3
  sub  s1, s1, s3
  li   t1, N_ITER
  sub  s4, t1, s4                # s4 = taken 횟수
  ret
