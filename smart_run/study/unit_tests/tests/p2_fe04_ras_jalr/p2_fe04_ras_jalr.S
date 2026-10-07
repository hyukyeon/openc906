# ============================================================================
# p2_fe04_ras_jalr : 함수 호출/복귀 예측 - RAS(4-entry) 와 JALR
#
#  - jal/jalr 로 ra 에 링크하면 IP 단계가 RAS 에 push, ret(jalr x0,0(ra)) 에서 pop 해 예측.
#  - RAS 는 4 엔트리(aq_ifu_ras.v). 호출 깊이가 4 를 넘으면 가장 오래된 주소를 덮어쓴다.
#  - rs1 != ra 인 JALR(함수 포인터 호출 등)은 예측하지 않는다:
#      aq_iu_bju.v  bju_pc_reg_mispred = bju_inst_jalr && src0_reg != x1  -> EX1 에서 항상 redirect
#
#  MARK 1..8 : 서로 다른 함수 f1->f2->...->fN 깊이 N 호출 (warm), 사이클 보고
#  MARK 11   : 직접 호출 jal  leaf  x32
#  MARK 12   : 간접 호출 jalr leaf(t3) x32     (rs1 = t3 != ra -> 매번 redirect)
#  MARK 13   : 직접 호출 x32, RAS 끔(MHCR.RS=0) -> ret 마다 redirect
# GTKW: fe ras ex rt
# ============================================================================
#include "study.h"

#define N_CALL 32

/* f\k : 깊이 카운터 a0 가 0 이 아니면 다음 함수 호출 */
.macro FN k, next
  .balign 16
f\k:
  addi sp, sp, -16
  sd   ra, 0(sp)
  addi a0, a0, -1
  beqz a0, .Lret\k
  jal  ra, f\next
.Lret\k:
  ld   ra, 0(sp)
  addi sp, sp, 16
  ret
.endm

.macro DEPTH_RUN d
  li   a0, \d
  jal  ra, f1                    # warm-up
  li   a0, \d
  MARK(\d)
  TIC(s0)
  jal  ra, f1
  TOC(s0)
  MARK(0)
  REPORT "depth\d\()_cycles", s0
.endm

  .text
  .option norvc
  .globl main
main:
  SET_MHCR(MHCR_DEFAULT)
  DEPTH_RUN 1
  DEPTH_RUN 2
  DEPTH_RUN 3
  DEPTH_RUN 4
  DEPTH_RUN 5
  DEPTH_RUN 6
  DEPTH_RUN 7
  DEPTH_RUN 8

  # ------------------------------------------------ MARK 11 : direct call
  jal  ra, call_direct           # warm-up
  MARK(11)
  jal  ra, call_direct
  MARK(0)
  REPORT "direct_call_x32_cycles", s0

  # ------------------------------------------------ MARK 12 : indirect call (jalr via t3)
  jal  ra, call_indirect
  MARK(12)
  jal  ra, call_indirect
  MARK(0)
  REPORT "indirect_call_x32_cycles", s0

  # ------------------------------------------------ MARK 13 : RAS off
  SET_MHCR(MHCR_DEFAULT & ~MHCR_RS)
  jal  ra, call_direct
  MARK(13)
  jal  ra, call_direct
  MARK(0)
  SET_MHCR(MHCR_DEFAULT)
  REPORT "direct_call_x32_ras_off_cycles", s0
  j    pass

# ----------------------------------------------------------------------------
# call_direct / call_indirect : leaf 를 N_CALL 번 호출, s0 = 사이클
# ----------------------------------------------------------------------------
  .balign 64
call_direct:
  mv   s4, ra
  li   s2, N_CALL
  TIC(s0)
1:
  jal  ra, leaf
  addi s2, s2, -1
  bnez s2, 1b
  TOC(s0)
  mv   ra, s4
  ret

  .balign 64
call_indirect:
  mv   s4, ra
  la   t3, leaf
  li   s2, N_CALL
  TIC(s0)
1:
  jalr ra, 0(t3)                 # 함수 포인터 호출 : rs1 = t3
  addi s2, s2, -1
  bnez s2, 1b
  TOC(s0)
  mv   ra, s4
  ret

  .balign 16
leaf:
  addi a6, a6, 1
  ret

FN 1, 2
FN 2, 3
FN 3, 4
FN 4, 5
FN 5, 6
FN 6, 7
FN 7, 8
FN 8, 9
  .balign 16
f9:
  ret
