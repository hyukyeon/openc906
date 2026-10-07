# ============================================================================
# p2_fe03_bp_ghr : C906 BHT 는 "전역 히스토리(GHR)만으로" 인덱싱된다 (PC 미사용)
#
#  aq_ifu_bht.v : bht_idx = vghr[11:2], 카운터 선택 = vghr[2:0]
#                 pred_bht_pc / iu_ifu_bht_cur_pc 포트는 선언만 되고 쓰이지 않는다.
#
#  MARK 1 : 교대 패턴 T,N,T,N...      -> PC 인덱스 2-bit 카운터라면 매번 틀리지만
#                                        GHR 인덱스는 패턴을 학습한다
#  MARK 2 : 주기 3 패턴 T,T,N,...     -> 역시 학습
#  MARK 3 : 앨리어싱(aliasing)        -> 서로 다른 두 분기 A(항상 T)/B(항상 N)가
#                                        "같은 히스토리(1이 16개)" 뒤에 오면 같은 카운터를 공유해서 싸운다
#  MARK 4 : MARK 3 과 같은 구조에서 B 만 '항상 taken' 으로 바꾼 대조군 -> 싸움 없음
#
#  각 구간은 128 회 반복, HPM3(조건분기 mispredict)과 사이클을 보고한다.
#
#  [실험] make run T=p2_fe03_bp_ghr PATCH=gshare_lite
#    patches/gshare_lite/aq_ifu_bht.v 는 카운터 열 선택 3bit 에 PC[3:1] 을 XOR 한다.
#    B 는 2B 어긋난 주소에 두었으므로 PC[3:1] 이 4B 정렬된 filler 분기들과 달라 서로 분리된다.
# GTKW: fe bht ex rt
# ============================================================================
#include "study.h"

#define N_ITER 128

/* 항상 taken 인 조건 분기 1개 (GHR 에 1 을 하나 밀어 넣는다) */
.macro TAKEN1
  beqz zero, .Lt_\@
.Lt_\@:
.endm

  .text
  .option norvc
  .globl main
main:
  SET_MHCR(MHCR_DEFAULT)

  # ------------------------------------------------- MARK 1 : alternating
  INV_BP
  MARK(1)
  li   s2, N_ITER
  li   a4, 0
  csrr s3, mhpmcounter3
  csrr s4, mhpmcounter4
  TIC(s0)
  .balign 16
1:
  andi a5, a4, 1
  beqz a5, 2f                    # a4 짝수면 taken  -> T,N,T,N...
  addi a6, a6, 1
2:
  addi a4, a4, 1
  addi s2, s2, -1
  bnez s2, 1b
  TOC(s0)
  csrr s1, mhpmcounter3
  sub  s1, s1, s3
  csrr s5, mhpmcounter4
  sub  s5, s5, s4
  MARK(0)
  REPORT "alt_cycles", s0
  REPORT "alt_mispred", s1
  REPORT "alt_condbr", s5

  # ------------------------------------------------- MARK 2 : period-3 (T,T,N)
  INV_BP
  MARK(2)
  li   s2, N_ITER
  li   a4, 2                     # a4 = 2,1,0,2,1,0,...
  csrr s3, mhpmcounter3
  TIC(s0)
  .balign 16
1:
  bnez a4, 2f                    # a4 != 0 이면 taken -> T,T,N 반복
  li   a4, 3
2:
  addi a4, a4, -1
  addi s2, s2, -1
  bnez s2, 1b
  TOC(s0)
  csrr s1, mhpmcounter3
  sub  s1, s1, s3
  MARK(0)
  REPORT "p3_cycles", s0
  REPORT "p3_mispred", s1

  # ------------------------------------------------- MARK 3 : aliasing
  # 반복마다:  [T x16] A(항상 taken)  [T x16] B(항상 not-taken)  loop
  # A, B 직전 히스토리가 둘 다 '1' 16 개 -> 같은 BHT 엔트리/카운터 -> 서로 덮어씀
  INV_BP
  MARK(3)
  li   s2, N_ITER
  csrr s3, mhpmcounter3
  TIC(s0)
  .balign 16
1:
  .rept 16
  TAKEN1
  .endr
branch_A_alias:
  beqz zero, 2f                  # A : 항상 taken
  nop
2:
  .rept 16
  TAKEN1
  .endr
  .option push
  .option rvc
  c.nop                          # B 를 2B 어긋난 주소(PC[1]=1)에 둔다 -> PC[3:1] 이 filler 분기들과 겹치지 않음
  .option pop
branch_B_alias:
  bnez zero, .Lfail_local        # B : 항상 not-taken
                                 # (주의: 'bnez zero, fail' 처럼 다른 파일의 전역 심볼을 쓰면
                                 #  GAS 가 'beqz zero,+8 ; j fail' 로 relax 해서 taken 분기가 된다)
  addi s2, s2, -1
  bnez s2, 1b
  TOC(s0)
  csrr s1, mhpmcounter3
  sub  s1, s1, s3
  MARK(0)
  REPORT "alias_cycles", s0
  REPORT "alias_mispred", s1

  # ------------------------------------------------- MARK 4 : control
  # 구조/분기 수는 MARK 3 과 같고, B 만 "항상 taken" 으로 바꾼 대조군.
  # 같은 카운터를 공유해도 방향이 같으므로 싸움이 없다 -> mispredict 가 사라져야 한다.
  INV_BP
  MARK(4)
  li   s2, N_ITER
  csrr s3, mhpmcounter3
  TIC(s0)
  .balign 16
1:
  .rept 16
  TAKEN1
  .endr
branch_A_ctrl:
  beqz zero, 2f
  nop
2:
  .rept 16
  TAKEN1
  .endr
  .option push
  .option rvc
  c.nop
  .option pop
branch_B_ctrl:
  beqz zero, 3f                  # B' : 항상 taken
3:
  addi s2, s2, -1
  bnez s2, 1b
  TOC(s0)
  csrr s1, mhpmcounter3
  sub  s1, s1, s3
  MARK(0)
  REPORT "ctrl_cycles", s0
  REPORT "ctrl_mispred", s1

  j    pass
.Lfail_local:
  j    fail
