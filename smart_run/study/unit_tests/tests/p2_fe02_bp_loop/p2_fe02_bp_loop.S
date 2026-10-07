# ============================================================================
# p2_fe02_bp_loop : 루프 분기로 보는 분기 예측기 3단 구조 (BTB / IP-stage / BJU)
#
#  같은 루프(본문 4개 ALU + bnez)를 예측기 설정을 바꿔가며 64회 실행한다.
#    MARK 1 : BPE=1 BTB=1 (기본)          -> taken 분기를 IF 단계 BTB 가 0-bubble 로 처리
#    MARK 2 : BPE=1 BTB=0                 -> IP 단계(pred)에서 redirect -> taken 마다 bubble
#    MARK 3 : BPE=0 (방향 예측 끔)        -> 항상 not-taken 취급 -> taken 마다 BJU 에서 flush
#  각 설정에서 BHT/BTB 를 무효화한 뒤 cold 1회 + warm 1회 실행하고
#  사이클과 HPM(조건분기 mispredict 수)을 보고한다.
#
#  보는 법: out/p2_fe02_bp_loop/pipeview.txt 의 MARK 1/2/3 구간에서
#           BTB-redirect / IP-redirect / MISPRED(BHT) 이벤트를 비교.
# GTKW: fe bht id ex rt
# ============================================================================
#include "study.h"

#define N_ITER 64

  .text
  .option norvc                  # 측정 구간은 32-bit 명령만 사용 (fetch 4B/cycle 와 1:1)
  .globl main
main:
  # ---------------------------------------------------------------- config 1
  SET_MHCR(MHCR_DEFAULT)
  INV_BP
  MARK(1)
  jal  ra, run_loop              # cold
  mv   s5, s0
  mv   s6, s1
  jal  ra, run_loop              # warm
  MARK(0)
  REPORT "cfg1_btb_on_cold_cycles", s5
  REPORT "cfg1_btb_on_cold_mispred", s6
  REPORT "cfg1_btb_on_warm_cycles", s0
  REPORT "cfg1_btb_on_warm_mispred", s1

  # ---------------------------------------------------------------- config 2
  SET_MHCR(MHCR_DEFAULT & ~MHCR_BTB)
  INV_BP
  MARK(2)
  jal  ra, run_loop
  mv   s5, s0
  mv   s6, s1
  jal  ra, run_loop
  MARK(0)
  REPORT "cfg2_btb_off_cold_cycles", s5
  REPORT "cfg2_btb_off_cold_mispred", s6
  REPORT "cfg2_btb_off_warm_cycles", s0
  REPORT "cfg2_btb_off_warm_mispred", s1

  # ---------------------------------------------------------------- config 3
  SET_MHCR(MHCR_DEFAULT & ~(MHCR_BTB | MHCR_BPE))
  INV_BP
  MARK(3)
  jal  ra, run_loop
  mv   s5, s0
  mv   s6, s1
  jal  ra, run_loop
  MARK(0)
  REPORT "cfg3_bpe_off_cold_cycles", s5
  REPORT "cfg3_bpe_off_cold_mispred", s6
  REPORT "cfg3_bpe_off_warm_cycles", s0
  REPORT "cfg3_bpe_off_warm_mispred", s1

  # 빈 측정(오버헤드) : TIC/TOC 사이에 아무것도 없을 때
  TIC(s0)
  TOC(s0)
  REPORT "empty_tic_toc_cycles", s0

  SET_MHCR(MHCR_DEFAULT)
  j    pass

# ----------------------------------------------------------------------------
# run_loop : s0 = 경과 사이클, s1 = 조건분기 mispredict(HPM3) 증가분
#            루프 = addi x4 + addi(counter) + bnez  (반복당 6 명령)
# ----------------------------------------------------------------------------
  .balign 64
run_loop:
  li   s2, N_ITER
  li   a4, 0
  csrr s3, mhpmcounter3
  TIC(s0)
  .balign 16
1:
  addi a4, a4, 1
  addi a5, a4, 2
  addi a6, a4, 3
  addi a7, a4, 4
  addi s2, s2, -1
  bnez s2, 1b                    # 63 번 taken, 마지막 1 번 not-taken
  TOC(s0)
  csrr s1, mhpmcounter3
  sub  s1, s1, s3
  ret
