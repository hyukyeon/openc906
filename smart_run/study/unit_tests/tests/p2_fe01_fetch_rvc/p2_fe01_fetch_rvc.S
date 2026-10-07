# ============================================================================
# p2_fe01_fetch_rvc : 명령어 fetch 와 RVC(16-bit 압축 명령)
#
#  C906 IFU 는 사이클당 4B(32bit) 를 fetch 한다 (aq_ifu_pcgen.v: pcgen_ifpc_inc = pc[63:2]+4).
#  4B 안에 16-bit 명령이 2 개 들어오면 IP 단계에서 inst0/inst1 두 개를 동시에 본다.
#  하지만 디코드/실행은 single-issue 라 IPC 상한은 1 이다.
#
#  MARK 1 : 32-bit addi 32 개 (정렬)            cold / warm
#  MARK 2 : 16-bit c.addi 32 개                  cold / warm   -> 코드 크기 절반 = I$ miss 감소
#  MARK 3 : 32-bit addi 32 개, 2B 어긋난 주소    warm          -> 한 명령이 두 fetch 블록에 걸침
#  보고: 사이클, I-Cache miss(HPM5)
# GTKW: fe id ex rt bus
# ============================================================================
#include "study.h"

/* 측정 블록 함수: s0 = 경과 사이클, s1 = I$ miss 증가분 */
.macro BLOCK_BEGIN name
  .balign 64
\name:
  csrr s3, mhpmcounter5
  TIC(s0)
.endm
.macro BLOCK_END
  TOC(s0)
  csrr s1, mhpmcounter5
  sub  s1, s1, s3
  ret
.endm

  .text
  .option norvc
  .globl main
main:
  # ------------------------------------------------ MARK 1 : 32-bit aligned
  MARK(1)
  jal  ra, blk_32bit
  mv   s5, s0
  mv   s6, s1
  jal  ra, blk_32bit
  MARK(0)
  REPORT "rv32_cold_cycles", s5
  REPORT "rv32_cold_icmiss", s6
  REPORT "rv32_warm_cycles", s0
  REPORT "rv32_warm_icmiss", s1

  # ------------------------------------------------ MARK 2 : 16-bit RVC
  MARK(2)
  jal  ra, blk_rvc
  mv   s5, s0
  mv   s6, s1
  jal  ra, blk_rvc
  MARK(0)
  REPORT "rvc_cold_cycles", s5
  REPORT "rvc_cold_icmiss", s6
  REPORT "rvc_warm_cycles", s0
  REPORT "rvc_warm_icmiss", s1

  # ------------------------------------------------ MARK 3 : 32-bit misaligned
  jal  ra, blk_32bit_mis         # warm-up
  MARK(3)
  jal  ra, blk_32bit_mis
  MARK(0)
  REPORT "rv32_misaligned_warm_cycles", s0

  # 기준: 빈 블록
  jal  ra, blk_empty
  jal  ra, blk_empty
  REPORT "empty_block_cycles", s0
  j    pass

# ----------------------------------------------------------------------------
BLOCK_BEGIN blk_32bit
  .rept 8
  addi a4, a4, 1
  addi a5, a5, 1
  addi a6, a6, 1
  addi a7, a7, 1
  .endr
BLOCK_END

  .option push
  .option rvc
BLOCK_BEGIN blk_rvc
  .rept 8
  c.addi a4, 1
  c.addi a5, 1
  c.addi a2, 1
  c.addi a3, 1
  .endr
  .option norvc
BLOCK_END
  .option pop

  .option push
  .option rvc
  .balign 64
blk_32bit_mis:
  csrr s3, mhpmcounter5
  TIC(s0)
  c.nop                          # 2B 밀어서 이후 32-bit 명령들을 halfword 경계에 놓는다
  .option norvc
  .rept 8
  addi a4, a4, 1
  addi a5, a5, 1
  addi a6, a6, 1
  addi a7, a7, 1
  .endr
  .option rvc
  c.nop                          # 다시 4B 정렬
  .option norvc
  TOC(s0)
  csrr s1, mhpmcounter5
  sub  s1, s1, s3
  ret
  .option pop

BLOCK_BEGIN blk_empty
BLOCK_END
