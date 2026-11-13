# ============================================================================
# p3_be05_hazard_dist : hazard 심화 - 거리, 같은 rd 재사용(WBT cnt), WAW, 소비자 종류, CSR/fence
#
#  p3_be01 은 "바로 다음 명령" 한 가지 거리만 쟀다. 여기서는
#   (1) 생산자-소비자 거리를 1/2/3 으로 바꿔 stall 이 언제 사라지는지
#   (2) 같은 rd 를 연달아 쓰면 WBT 의 cnt(진행 중인 writer 수)가 2 가 되어
#       forward 예외가 꺼지는 경우 (aq_idu_id_ctrl.v:431-445, aq_idu_id_wbt_entry.v:126-153)
#   (3) 생산자별 WAW
#   (4) 소비자 종류(store 데이터/주소, mul 피연산자, 조건분기)
#   (5) CSR 읽기/쓰기와 fence 의 직렬화 비용
#  각 블록은 두 번 실행하고 두 번째(warm) 사이클을 보고한다. 블록 = N 명령이면 이상적으로 N+3.
#
#  MARK 1-3   : ld  -> 사용, 거리 1/2/3          (블록 32/48/64 명령)
#  MARK 4-6   : mul -> 사용, 거리 1/2/3
#  MARK 7-9   : mul(64bit 큰 값, split) -> 사용, 거리 1/4/7 (블록 16/40/64 명령)
#  MARK 10    : ld a4 ; bnez a4  x16               (같은 rd 연속 -> cnt 2)
#  MARK 11    : ld a4 ; bnez a4 ; ld a5 ; bnez a5  (rd 번갈아 -> cnt 1)
#  MARK 12    : ld a4 ; addi a6,a4  x16          (거리 1, 같은 rd)
#  MARK 13    : ld a4/a5 번갈아 ; addi 사용       (거리 1, rd 번갈아)
#  MARK 14    : mul a4 ; addi a6,s4 ; addi a7,a4 (거리 2, 같은 rd)
#  MARK 15    : mul a4/a5 번갈아, 거리 2
#  MARK 16    : WAW mul a4 ; li a4
#  MARK 17    : WAW ld a4 ; ld a4                (load 끼리)
#  MARK 18    : WAW li a4 ; ld a4                (ALU 다음 load)
#  MARK 19    : WAW mul a4 ; mul a4
#  MARK 20    : mul a4 ; sd a4 (store 데이터)
#  MARK 21    : ld a4 ; mul a5,a4,s5
#  MARK 22    : ld a4 ; sd a4 (store 데이터, 예외 4)  / MARK 23 : ld 주소 -> sd 주소
#  MARK 24    : (addi x3 ; csrr mstatus) x8
#  MARK 25    : (addi x3 ; csrw sscratch) x8
#  MARK 26    : (addi x3 ; fence) x8
#  MARK 27    : (addi x3 ; fence.i) x4
#  MARK 28    : 빈 블록 (기준 3)
# GTKW: id pipe ex rt
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
  la   s8, data0                 # data0 = 0
  la   s9, ptr0                  # ptr0 -> 자기 자신
  ld   a1, 0(s8)
  ld   a1, 0(s9)
  li   s4, 3
  li   s5, 5
  li   s6, 0x123456789abcdef
  li   s7, 0x0fedcba987654321

  MEASURE ld_use_d1,        1
  MEASURE ld_use_d2,        2
  MEASURE ld_use_d3,        3
  MEASURE mul_use_d1,       4
  MEASURE mul_use_d2,       5
  MEASURE mul_use_d3,       6
  MEASURE mulbig_use_d1,    7
  MEASURE mulbig_use_d4,    8
  MEASURE mulbig_use_d7,    9
  MEASURE ld_br_same_rd,   10
  MEASURE ld_br_alt_rd,    11
  MEASURE ld_use_same_rd,  12
  MEASURE ld_use_alt_rd,   13
  MEASURE mul_d2_same_rd,  14
  MEASURE mul_d2_alt_rd,   15
  MEASURE waw_mul_alu,     16
  MEASURE waw_ld_ld,       17
  MEASURE waw_alu_ld,      18
  MEASURE waw_mul_mul,     19
  MEASURE mul_sd_data,     20
  MEASURE ld_mul_src,      21
  MEASURE ld_sd_data,      22
  MEASURE ld_sd_addr,      23
  MEASURE csrr_x8,         24
  MEASURE csrw_x8,         25
  MEASURE fence_x8,        26
  MEASURE fencei_x4,       27
  MEASURE empty,           28
  j    pass

# ---------------------------------------------------------------------------- 거리
BLOCK ld_use_d1
  .rept 16
  ld   a4, 0(s8)
  addi a5, a4, 1
  .endr
ENDBLOCK

BLOCK ld_use_d2
  .rept 16
  ld   a4, 0(s8)
  addi a6, s4, 1
  addi a5, a4, 1
  .endr
ENDBLOCK

BLOCK ld_use_d3
  .rept 16
  ld   a4, 0(s8)
  addi a6, s4, 1
  addi a7, s4, 1
  addi a5, a4, 1
  .endr
ENDBLOCK

BLOCK mul_use_d1
  .rept 16
  mul  a4, s4, s5
  addi a5, a4, 1
  .endr
ENDBLOCK

BLOCK mul_use_d2
  .rept 16
  mul  a4, s4, s5
  addi a6, s4, 1
  addi a5, a4, 1
  .endr
ENDBLOCK

BLOCK mul_use_d3
  .rept 16
  mul  a4, s4, s5
  addi a6, s4, 1
  addi a7, s4, 1
  addi a5, a4, 1
  .endr
ENDBLOCK

BLOCK mulbig_use_d1
  .rept 8
  mul  a4, s6, s7
  addi a5, a4, 1
  .endr
ENDBLOCK

BLOCK mulbig_use_d4
  .rept 8
  mul  a4, s6, s7
  addi a6, s4, 1
  addi a7, s4, 1
  addi t3, s4, 1
  addi a5, a4, 1
  .endr
ENDBLOCK

BLOCK mulbig_use_d7
  .rept 8
  mul  a4, s6, s7
  REPEAT 6, addi a6, s4, 1
  addi a5, a4, 1
  .endr
ENDBLOCK

# ---------------------------------------------------------------------------- 같은 rd 재사용 (WBT cnt)
BLOCK ld_br_same_rd
  .rept 16
  ld   a4, 0(s8)
  bnez a4, 9f                    # data0 = 0 -> not taken
  .endr
9:
ENDBLOCK

BLOCK ld_br_alt_rd
  .rept 8
  ld   a4, 0(s8)
  bnez a4, 9f
  ld   a5, 0(s8)
  bnez a5, 9f
  .endr
9:
ENDBLOCK

BLOCK ld_use_same_rd
  .rept 16
  ld   a4, 0(s8)
  addi a6, a4, 1
  .endr
ENDBLOCK

BLOCK ld_use_alt_rd
  .rept 8
  ld   a4, 0(s8)
  addi a6, a4, 1
  ld   a5, 0(s8)
  addi a7, a5, 1
  .endr
ENDBLOCK

BLOCK mul_d2_same_rd
  .rept 16
  mul  a4, s4, s5
  addi a6, s4, 1
  addi a7, a4, 1
  .endr
ENDBLOCK

BLOCK mul_d2_alt_rd
  .rept 8
  mul  a4, s4, s5
  addi a6, s4, 1
  addi a7, a4, 1
  mul  a5, s4, s5
  addi a6, s4, 1
  addi a7, a5, 1
  .endr
ENDBLOCK

# ---------------------------------------------------------------------------- WAW
BLOCK waw_mul_alu
  .rept 16
  mul  a4, s4, s5
  li   a4, 7
  .endr
ENDBLOCK

BLOCK waw_ld_ld
  .rept 16
  ld   a4, 0(s8)
  ld   a4, 8(s8)
  .endr
ENDBLOCK

BLOCK waw_alu_ld
  .rept 16
  li   a4, 7
  ld   a4, 0(s8)
  .endr
ENDBLOCK

BLOCK waw_mul_mul
  .rept 16
  mul  a4, s4, s5
  mul  a4, s5, s4
  .endr
ENDBLOCK

# ---------------------------------------------------------------------------- 소비자 종류
BLOCK mul_sd_data
  .rept 16
  mul  a4, s4, s5
  sd   a4, 8(s8)
  .endr
ENDBLOCK

BLOCK ld_mul_src
  .rept 16
  ld   a4, 0(s8)
  mul  a5, a4, s5
  .endr
ENDBLOCK

BLOCK ld_sd_data
  .rept 16
  ld   a4, 0(s8)
  sd   a4, 8(s8)
  .endr
ENDBLOCK

BLOCK ld_sd_addr
  .rept 16
  ld   a4, 0(s9)                 # a4 = ptr0
  sd   s4, 8(a4)
  .endr
ENDBLOCK

# ---------------------------------------------------------------------------- 직렬화
BLOCK csrr_x8
  .rept 8
  addi a5, s4, 1
  addi a6, s4, 1
  addi a7, s4, 1
  csrr a4, mstatus
  .endr
ENDBLOCK

BLOCK csrw_x8
  .rept 8
  addi a5, s4, 1
  addi a6, s4, 1
  addi a7, s4, 1
  csrw sscratch, s4
  .endr
ENDBLOCK

BLOCK fence_x8
  .rept 8
  addi a5, s4, 1
  addi a6, s4, 1
  addi a7, s4, 1
  fence
  .endr
ENDBLOCK

BLOCK fencei_x4
  .rept 4
  addi a5, s4, 1
  addi a6, s4, 1
  addi a7, s4, 1
  fence.i
  .endr
ENDBLOCK

BLOCK empty
ENDBLOCK

# ---------------------------------------------------------------------------- data
  .data
  .balign 64
data0:  .dword 0, 0, 0, 0
ptr0:   .dword ptr0, 0
