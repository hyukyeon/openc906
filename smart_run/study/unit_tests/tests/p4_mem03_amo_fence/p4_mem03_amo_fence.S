# ============================================================================
# p4_mem03_amo_fence : A 확장(LR/SC, AMO) 과 FENCE / FENCE.I
#
#  RISC-V A 확장
#   lr.d rd,(a)      : load + reservation 등록
#   sc.d rd,rs2,(a)  : reservation 이 유효하면 store, rd=0 (성공) / 아니면 rd!=0 (실패)
#   amoXXX.d rd,rs2,(a) : rd <- M[a];  M[a] <- op(M[a], rs2)  을 원자적으로
#  C906 은 IDU 가 AMO 를 split 해서 LSU 가 read-modify-write 로 처리, reservation 은 aq_lsu_amr.v
#
#  MARK 1 : lr.d / sc.d  성공
#  MARK 2 : sc.d 단독(reservation 없음) -> 실패
#  MARK 3 : lr.d; 같은 주소에 일반 sd; sc.d -> ?
#  MARK 4 : amoadd.d / amoswap.d / amomax.d 결과 확인 + amoadd 사이클 vs ld+add+sd
#  MARK 5 : fence rw,rw 사이클
#  MARK 6 : fence.i 사이클과 직후 I-Cache miss
# GTKW: id ex lsu rt bus
# ============================================================================
#include "study.h"

  .text
  .option norvc
  .globl main
main:
  la   s8, var
  ld   a4, 0(s8)                 # warm

  # ------------------------------------------------ MARK 1 : LR/SC success
  li   a2, 111
  MARK(1)
  lr.d a4, (s8)
  sc.d a5, a2, (s8)
  MARK(0)
  ld   a6, 0(s8)
  REPORT "lrsc_sc_result(0=ok)", a5
  REPORT "lrsc_mem_after", a6

  # ------------------------------------------------ MARK 2 : SC without LR
  li   a2, 222
  MARK(2)
  sc.d a5, a2, (s8)
  MARK(0)
  ld   a6, 0(s8)
  REPORT "sc_alone_result", a5
  REPORT "sc_alone_mem_after", a6

  # ------------------------------------------------ MARK 3 : LR; store; SC
  li   a2, 333
  li   a3, 999
  MARK(3)
  lr.d a4, (s8)
  sd   a3, 0(s8)                 # 같은 hart 의 일반 store
  sc.d a5, a2, (s8)
  MARK(0)
  ld   a6, 0(s8)
  REPORT "lr_sd_sc_result", a5
  REPORT "lr_sd_sc_mem_after", a6

  # ------------------------------------------------ MARK 4 : AMO
  li   t1, 10
  sd   t1, 0(s8)
  li   a2, 5
  MARK(4)
  amoadd.d  a4, a2, (s8)         # a4 = 10, M = 15
  amoswap.d a5, a2, (s8)         # a5 = 15, M = 5
  li   a3, 77
  amomax.d  a6, a3, (s8)         # a6 = 5,  M = 77
  MARK(0)
  ld   a7, 0(s8)
  REPORT "amoadd_old", a4
  REPORT "amoswap_old", a5
  REPORT "amomax_old", a6
  REPORT "mem_final", a7

  li   s6, 2                     # 2 회 측정 (두 번째 = warm)
1:
  MARK(5)
  TIC(s0)
  amoadd.d a4, a2, (s8)
  TOC(s0)
  TIC(s1)
  ld   a4, 0(s8)
  add  a4, a4, a2
  sd   a4, 0(s8)
  TOC(s1)
  TIC(s2)
  fence rw, rw
  TOC(s2)
  MARK(0)
  addi s6, s6, -1
  bnez s6, 1b
  REPORT "amoadd_cycles", s0
  REPORT "ld_add_sd_cycles", s1
  REPORT "fence_rw_rw_cycles", s2

  # ------------------------------------------------ MARK 6 : fence.i
  jal  ra, small_func            # I$ 에 올려 둠
  TIC(s0)
  jal  ra, small_func
  TOC(s0)
  REPORT "small_func_warm_cycles", s0
  csrr s4, mhpmcounter5
  MARK(6)
  TIC(s1)
  fence.i                        # C906: I-Cache 전체 무효화
  TOC(s1)
  TIC(s0)
  jal  ra, small_func            # 다시 miss
  TOC(s0)
  MARK(0)
  csrr t1, mhpmcounter5
  sub  s4, t1, s4
  REPORT "fence_i_cycles", s1
  REPORT "small_func_after_fence_i_cycles", s0
  REPORT "icache_miss_after_fence_i", s4
  j    pass

  .balign 64
small_func:
  .rept 8
  addi a4, a4, 1
  .endr
  ret

  .data
  .balign 64
var: .dword 0
