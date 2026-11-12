# ============================================================================
# p2_fe05_rvc_density : 압축 명령(RVC) 의 효과 - 코드 크기, I-Cache miss, 사이클, 정렬
#
#  같은 일(addi a0, a0, 1 x 256)을 두 가지로 만든다.
#    blk_rvc   : .option rvc   -> c.addi (2B) x 256 = 512B  = I-Cache 라인(64B) 8 개
#    blk_norvc : .option norvc -> addi   (4B) x 256 = 1024B = 라인 16 개
#  MARK 1 / 2 : 처음 실행(cold) - 사이클과 I-Cache miss 수(mhpmcounter5 = HPM_IC_MISS)
#  MARK 3 / 4 : 두 번째 실행(warm) - 캐시에 다 들어 있을 때
#  MARK 5 / 6 : 32-bit 명령 루프 - 4 바이트 경계에 맞춘 경우 vs 2 바이트 어긋난 경우 (warm, 16 회)
# GTKW: fe rt
# ZOOM: mark
# ============================================================================
#include "study.h"
  .option norelax                 # .balign 이 링커 relaxation 과 충돌하지 않게

#define IC_MISS  mhpmcounter5

.macro MEASURE fn, mark, cyc, miss
  csrr \miss, IC_MISS
  MARK(\mark)
  TIC(\cyc)
  jal  ra, \fn
  TOC(\cyc)
  MARK(0)
  csrr t0, IC_MISS
  sub  \miss, t0, \miss
.endm

  .text
  .globl main
main:
  # ---------------------------------------------------------------- 크기
  la   t0, blk_rvc
  la   t1, blk_rvc_end
  sub  s1, t1, t0
  REPORT "size_rvc_bytes", s1
  la   t0, blk_norvc
  la   t1, blk_norvc_end
  sub  s1, t1, t0
  REPORT "size_norvc_bytes", s1

  # ---------------------------------------------------------------- MARK 1 / 2 : cold
  li   a0, 0
  MEASURE blk_rvc, 1, s2, s3
  EXPECT a0, 256
  REPORT "m1_rvc_cold_cycles", s2
  REPORT "m1_rvc_cold_icmiss", s3
  li   a0, 0
  MEASURE blk_norvc, 2, s4, s5
  EXPECT a0, 256
  REPORT "m2_norvc_cold_cycles", s4
  REPORT "m2_norvc_cold_icmiss", s5

  # ---------------------------------------------------------------- MARK 3 / 4 : warm
  MEASURE blk_rvc, 3, s2, s3
  REPORT "m3_rvc_warm_cycles", s2
  REPORT "m3_rvc_warm_icmiss", s3
  MEASURE blk_norvc, 4, s4, s5
  REPORT "m4_norvc_warm_cycles", s4
  REPORT "m4_norvc_warm_icmiss", s5

  # ---------------------------------------------------------------- MARK 5 / 6 : 정렬
  jal  ra, loop_aligned           # 한 번 돌려 캐시를 데운다
  jal  ra, loop_misaligned
  MEASURE loop_aligned, 5, s6, s7
  REPORT "m5_aligned32_loop_cycles", s6
  MEASURE loop_misaligned, 6, s8, s9
  REPORT "m6_misaligned32_loop_cycles", s8
  j    pass

# ----------------------------------------------------------------------------
  .option push
  .option rvc
  .balign 64
blk_rvc:
  .rept 256
  c.addi a0, 1
  .endr
  ret
blk_rvc_end:
  .option pop

  .option push
  .option norvc
  .balign 64
blk_norvc:
  .rept 256
  addi a0, a0, 1
  .endr
  ret
blk_norvc_end:
  .option pop

# 32-bit 명령 8 개짜리 루프를 16 번. 첫 명령 주소가 4 의 배수인 경우와 2 만큼 어긋난 경우.
  .option push
  .option norvc
  .balign 64
loop_aligned:
  li   t1, 16
1:
  add  t2, t2, t1
  add  t3, t3, t1
  add  t4, t4, t1
  add  t5, t5, t1
  add  t2, t2, t1
  add  t3, t3, t1
  addi t1, t1, -1
  bnez t1, 1b
  ret
  .option pop

  .option push
  .option rvc
  .balign 64
loop_misaligned:
  c.nop                           # 2 바이트 -> 뒤의 32-bit 명령들이 모두 4 바이트 경계를 걸친다
  .option norvc
  li   t1, 16
2:
  add  t2, t2, t1
  add  t3, t3, t1
  add  t4, t4, t1
  add  t5, t5, t1
  add  t2, t2, t1
  add  t3, t3, t1
  addi t1, t1, -1
  bnez t1, 2b
  ret
  .option pop
