# ============================================================================
# p4_mem02_stb : Store Buffer 와 store-to-load forwarding
#
#  store 는 retire 후 STB(aq_lsu_stb.v)에 머물다가 D-Cache 로 내려간다.
#  뒤따르는 load 가 STB 에 있는 주소를 읽으면 STB 에서 데이터를 받는다(forwarding).
#  단, load 가 요구하는 바이트를 store 가 모두 덮고 있어야 한다.
#
#  각 블록: (store, load) 쌍 x16, warm 실행 사이클 보고 (32 명령 -> 이상적 35)
#   MARK 1 : sd A ; ld A          같은 주소, 같은 크기   -> forward
#   MARK 2 : sd A ; ld A+64       다른 line (D$ hit)     -> 기준
#   MARK 3 : sd A ; lw A+4        store 가 load 를 포함  -> forward?
#   MARK 4 : sw A ; ld A          load 가 store 보다 큼  -> forward 불가
#   MARK 5 : sb A ; lbu A         바이트
# GTKW: lsu rt
# ============================================================================
#include "study.h"

.macro BLOCK name
  .balign 64
\name:
  TIC(s0)
.endm
.macro ENDBLOCK
  TOC(s0)
  ret
.endm
.macro MEASURE name, mark
  jal  ra, \name
  MARK(\mark)
  jal  ra, \name
  MARK(0)
  REPORT "\name", s0
.endm

  .text
  .option norvc
  .globl main
main:
  la   s8, buf
  ld   a4, 0(s8)                 # line 데우기
  ld   a4, 64(s8)
  li   a2, 0x55

  MEASURE sd_ld_same,     1
  MEASURE sd_ld_other,    2
  MEASURE sd_lw_inside,   3
  MEASURE sw_ld_partial,  4
  MEASURE sb_lbu_same,    5
  j    pass

BLOCK sd_ld_same
  .rept 16
  sd   a2, 0(s8)
  ld   a4, 0(s8)
  .endr
ENDBLOCK

BLOCK sd_ld_other
  .rept 16
  sd   a2, 0(s8)
  ld   a4, 64(s8)
  .endr
ENDBLOCK

BLOCK sd_lw_inside
  .rept 16
  sd   a2, 0(s8)
  lw   a4, 4(s8)
  .endr
ENDBLOCK

BLOCK sw_ld_partial
  .rept 16
  sw   a2, 0(s8)
  ld   a4, 0(s8)
  .endr
ENDBLOCK

BLOCK sb_lbu_same
  .rept 16
  sb   a2, 0(s8)
  lbu  a4, 0(s8)
  .endr
ENDBLOCK

  .data
  .balign 64
buf: .space 256
