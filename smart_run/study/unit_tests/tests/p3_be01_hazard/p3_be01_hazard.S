# ============================================================================
# p3_be01_hazard : 데이터 hazard 와 forwarding (IDU 의 WBT scoreboard)
#
#  aq_idu_id_ctrl.v 의 ctrl_dis_src*_raw_except 가 "RAW 지만 stall 하지 않는" 경우를 정의한다.
#   1) 생산자가 ALU/BJU        -> EX1 결과를 바로 forward (stall 0)
#   2) 생산자가 LOAD, 소비자가 조건분기 -> BJU 가 결과를 기다림 (ID stall 없음)
#   3) 생산자 결과가 RTU forward 경로(fwd0~2)에 있음
#   4) 생산자가 LOAD, 소비자가 STORE 의 데이터(src2)
#  그 밖의 RAW(예: load-use, mul-use)는 ID 에서 stall.
#
#  각 블록은 "두 명령 쌍" x16 을 2 회 실행하고 두 번째(warm) 사이클을 보고한다.
#  블록 하나 = 32 명령 -> hazard 가 없으면 약 32+3 사이클.
# GTKW: id ex lsu rt
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
  la   s8, data0                 # data0 = 0 (8B), data0+8 = 스크래치
  la   s9, ptr0                  # ptr0 -> 자기 자신 (pointer chasing)
  ld   a1, 0(s8)                 # D$ 데우기
  ld   a1, 0(s9)
  li   a2, 3
  li   a3, 5

  MEASURE alu_indep,      1
  MEASURE alu_dep,        2
  MEASURE ld_use,         3
  MEASURE ld_indep,       4
  MEASURE ld_ld_chase,    5
  MEASURE mul_use,        6
  MEASURE mul_indep,      7
  MEASURE ld_branch,      8
  MEASURE ld_store_data,  9
  MEASURE ld_store_addr, 10
  MEASURE waw_ld_alu,    11
  MEASURE empty,         12
  j    pass

# ---------------------------------------------------------------------------- blocks
BLOCK alu_indep                  # 독립 ALU
  .rept 16
  addi a4, a4, 1
  addi a5, a5, 1
  .endr
ENDBLOCK

BLOCK alu_dep                    # ALU -> ALU 의존 (EX1 forward)
  .rept 16
  addi a4, a4, 1
  addi a4, a4, 1
  .endr
ENDBLOCK

BLOCK ld_use                     # load -> 바로 다음 명령이 사용
  .rept 16
  ld   a4, 0(s8)
  addi a5, a4, 1
  .endr
ENDBLOCK

BLOCK ld_indep                   # load 다음 독립 명령
  .rept 16
  ld   a4, 0(s8)
  addi a5, a3, 1
  .endr
ENDBLOCK

BLOCK ld_ld_chase                # load 결과가 다음 load 의 주소 (a1 = ptr0 -> ptr0)
  mv   a1, s9
  .rept 16
  ld   a1, 0(a1)
  addi a5, a3, 1
  .endr
ENDBLOCK

BLOCK mul_use                    # mul -> 바로 사용
  .rept 16
  mul  a4, a2, a3
  addi a5, a4, 1
  .endr
ENDBLOCK

BLOCK mul_indep                  # mul 다음 독립 명령
  .rept 16
  mul  a4, a2, a3
  addi a5, a3, 1
  .endr
ENDBLOCK

BLOCK ld_branch                  # load -> 조건분기 (예외 2)
  .rept 16
  ld   a4, 0(s8)
  bnez a4, 9f                    # data0 = 0 -> not taken
  .endr
9:
ENDBLOCK

BLOCK ld_store_data              # load -> store 의 데이터 (예외 4)
  .rept 16
  ld   a4, 0(s8)
  sd   a4, 8(s8)
  .endr
ENDBLOCK

BLOCK ld_store_addr              # load -> store 의 주소 (예외 아님 -> stall)
  .rept 16
  ld   a4, 0(s9)                 # a4 = ptr0 주소
  sd   a3, 8(a4)
  .endr
ENDBLOCK

BLOCK waw_ld_alu                 # load 가 쓰는 레지스터를 ALU 가 바로 덮어씀 (WAW)
  .rept 16
  ld   a4, 0(s8)
  li   a4, 7
  .endr
ENDBLOCK

BLOCK empty
ENDBLOCK

# ---------------------------------------------------------------------------- data
  .data
  .balign 64
data0:  .dword 0, 0, 0, 0
ptr0:   .dword ptr0, 0
