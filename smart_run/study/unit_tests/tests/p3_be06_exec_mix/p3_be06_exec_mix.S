# ============================================================================
# p3_be06_exec_mix : 유닛별 실행 흐름(EX1 -> retire -> write-back)과
#                    "같은 명령 연속" vs "다른 명령 섞기" 비교
#
#  - 모든 명령은 EX1 에서 complete -> 다음 사이클(EX2) retire (aq_rtu_ctrl.v:142-168)
#  - 결과를 레지스터에 쓰는 시점은 유닛마다 다르다
#      ALU/BJU/CP0 : EX1 결과 -> 다음 사이클 wb0
#      MUL         : EX3 결과 -> wb0 (grant 필요)
#      DIV         : 반복 끝(CMPLT) -> wb0 (grant 필요, 못 받으면 WFWB 상태로 대기)
#      LOAD        : DC(EX2) 데이터 -> 다음 사이클 wb1 (rbus 와 별개 포트)
#  - wb0(rbus) 중재 (aq_rtu_rbus.v:467-468) : EX1 결과 > DIV > MUL
#      EX1 에 ALU/BJU/LSU/CP0 명령이 있으면 DIV/MUL 은 그 사이클에 못 쓴다
#
#  MARK 1  : add 한 개 + 바로 사용                      (흐름 A)
#  MARK 2  : mul (작은 피연산자) + 바로 사용
#  MARK 3  : mul (64bit 큰 피연산자 -> split) + 바로 사용
#  MARK 4  : div 1000/3 + 바로 사용                     (흐름 B)
#  MARK 5  : ld hit + 바로 사용                          (흐름 C)
#  MARK 6  : ld miss + 바로 사용
#  MARK 7  : sd 한 개 + 같은 주소 ld
#  MARK 8  : div 1000/3 + 독립 ALU 4 개 + 사용           (DIV 와 ALU 겹치기)
#  MARK 9  : div 1000/3 + 독립 ALU 16 개 + 사용          (ALU 가 계속 오면 DIV 가 wb 를 못 함)
#  MARK 10 : ld miss + 독립 ALU 16 개 + 사용             (miss 중에도 뒤 명령이 retire 되는가)
#  MARK 11 : ld miss + 독립 ld hit 4 개                  (miss 중 다음 load)
#  MARK 12 : mul + 독립 ALU 16 개 + 사용                 (MUL 이 EX3 에서 grant 대기)
#  아래는 블록을 두 번 실행해 두 번째(warm) 값을 보고한다
#  MARK 20 : ALU x32 독립                (기준)
#  MARK 21 : mul x32 독립 (작은 값)
#  MARK 22 : mul x16 독립 (큰 값, split)
#  MARK 23 : ld  x32 독립 (hit)
#  MARK 24 : sd  x32 (다른 주소)
#  MARK 25 : div x4 독립 (1000/3)
#  MARK 26 : (mul, add) x16                      -- 다른 유닛 번갈아
#  MARK 27 : (mul, add, add) x11
#  MARK 28 : (ld, add) x16
#  MARK 29 : (ld, mul) x16                       -- wb1 과 wb0 동시
#  MARK 30 : (ld, sd) x16
#  MARK 31 : (div, add x10) x4                   -- DIV 반복 중 ALU
#  MARK 32 : (div, mul) x4
#  MARK 33 : (mul, ld, add) x11
# GTKW: pipe id ex rt
# ============================================================================
#include "study.h"

# 흐름 측정용 함수: FBEGIN 과 FSTART 사이가 준비(측정 밖), FSTART 부터 ENDBLOCK 까지가 측정 구간
.macro FBEGIN name
  .balign 64
\name:
.endm
.macro FSTART
  fence
  TIC(s0)
.endm

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

# 줄 s9 를 D-Cache 에서 지운다 (clean 라인이므로 데이터는 메모리에 그대로)
.macro DC_INV reg
  th.dcache.iva \reg
  th.sync
.endm

.macro OPERANDS
  li   s2, 1000
  li   s1, 1001
  li   s3, 3
  li   s4, 3
  li   s5, 5
  li   s6, 0x123456789abcdef
  li   s7, 0x0fedcba987654321
.endm

  .text
  .option norvc
  .option arch, +xtheadcmo, +xtheadsync
  .globl main
main:
  la   s8, data0                 # 쓰기 대상 (data0 .. +255)
  la   s9, miss0                 # miss 용 라인 (64B 마다 하나)
  la   s10, hitbuf               # hit 용
  ld   a4, 0(s10)
  ld   a4, 64(s10)
  OPERANDS
  mv   a4, s4
  mv   a5, s5

  # ------------------------------------------------------------ 흐름 (단일 명령)
  # 모든 측정은 함수를 두 번 부르고 두 번째 값을 쓴다 (I-Cache warm)
  MEASURE f1_add_use,            1
  MEASURE f2_mul_use,            2
  MEASURE f3_mul64big_use,       3
  MEASURE f4_div_use,            4
  MEASURE f5_ld_hit_use,         5
  MEASURE f6_ld_miss_use,        6
  MEASURE f7_sd_then_ld,         7
  MEASURE f8_div_4alu_use,       8
  MEASURE f9_div_16alu_use,      9
  MEASURE f10_ldmiss_16alu_use, 10
  MEASURE f11_ldmiss_4ldhit,    11
  MEASURE f12_mul_16alu_use,    12

  # ------------------------------------------------------------ 연속 / 섞기
  MEASURE alu_x32,        20
  MEASURE mul_x32,        21
  MEASURE mul64big_x16,   22
  MEASURE ld_x32,         23
  MEASURE sd_x32,         24
  MEASURE div_x4,         25
  MEASURE mul_add_x16,    26
  MEASURE mul_add_add_x11,27
  MEASURE ld_add_x16,     28
  MEASURE ld_mul_x16,     29
  MEASURE ld_sd_x16,      30
  MEASURE div_add10_x4,   31
  MEASURE div_mul_x4,     32
  MEASURE mul_ld_add_x11, 33
  j    pass

# ---------------------------------------------------------------------------- flows
FBEGIN f1_add_use
  FSTART
  add  a6, s4, s5
  addi a7, a6, 1
ENDBLOCK

FBEGIN f2_mul_use
  FSTART
  mul  a6, s4, s5
  addi a7, a6, 1
ENDBLOCK

FBEGIN f3_mul64big_use
  FSTART
  mul  a6, s6, s7
  addi a7, a6, 1
ENDBLOCK

FBEGIN f4_div_use
  addi a6, s2, 7
  divu a6, a6, s3                # 결과 버퍼를 다른 피연산자로 채운다
  FSTART
  divu a6, s2, s3
  addi a7, a6, 1
ENDBLOCK

FBEGIN f5_ld_hit_use
  FSTART
  ld   a6, 0(s10)
  addi a7, a6, 1
ENDBLOCK

FBEGIN f6_ld_miss_use
  DC_INV s9
  FSTART
  ld   a6, 0(s9)
  addi a7, a6, 1
ENDBLOCK

FBEGIN f7_sd_then_ld
  FSTART
  sd   s5, 32(s10)
  ld   a6, 32(s10)
ENDBLOCK

FBEGIN f8_div_4alu_use
  addi a6, s2, 7
  divu a6, a6, s3
  FSTART
  divu a6, s2, s3
  .rept 2
  addi a4, s4, 1
  addi a5, s4, 1
  .endr
  addi a7, a6, 1
ENDBLOCK

FBEGIN f9_div_16alu_use
  addi a6, s2, 7
  divu a6, a6, s3
  FSTART
  divu a6, s2, s3
  .rept 8
  addi a4, s4, 1
  addi a5, s4, 1
  .endr
  addi a7, a6, 1
ENDBLOCK

FBEGIN f10_ldmiss_16alu_use
  addi s11, s9, 64
  DC_INV s11
  FSTART
  ld   a6, 0(s11)
  .rept 8
  addi a4, s4, 1
  addi a5, s4, 1
  .endr
  addi a7, a6, 1
ENDBLOCK

FBEGIN f11_ldmiss_4ldhit
  addi s11, s9, 128
  DC_INV s11
  FSTART
  ld   a6, 0(s11)
  ld   a4, 0(s10)
  ld   a5, 8(s10)
  ld   a4, 16(s10)
  ld   a5, 24(s10)
ENDBLOCK

FBEGIN f12_mul_16alu_use
  FSTART
  mul  a6, s4, s5
  .rept 8
  addi a4, s4, 1
  addi a5, s4, 1
  .endr
  addi a7, a6, 1
ENDBLOCK

# ---------------------------------------------------------------------------- blocks
# 블록 안에서 쓰는 피연산자: s4=3 s5=5 (작은 값), s6/s7 (큰 값), s2=1000 s1=1001 s3=3
#  (div 는 결과 버퍼 hit 을 피하려고 s2/s1 을 번갈아 쓴다)
BLOCK alu_x32
  .rept 16
  addi a4, s4, 1
  addi a5, s5, 1
  .endr
ENDBLOCK

BLOCK mul_x32
  .rept 16
  mul  a4, s4, s5
  mul  a5, s5, s4
  .endr
ENDBLOCK

BLOCK mul64big_x16
  .rept 8
  mul  a4, s6, s7
  mul  a5, s7, s6
  .endr
ENDBLOCK

BLOCK ld_x32
  .rept 16
  ld   a4, 0(s10)
  ld   a5, 8(s10)
  .endr
ENDBLOCK

BLOCK sd_x32
  .set off, 0
  .rept 32
  sd   s4, off(s8)
  .set off, off + 8
  .endr
ENDBLOCK

BLOCK div_x4                     # 목적 레지스터를 모두 달리해 WAW 를 없앤다
  divu a4, s2, s3
  divu a5, s1, s3                # 피제수를 바꿔 결과 버퍼 hit 을 피한다
  divu a6, s2, s3
  divu a7, s1, s3
ENDBLOCK

BLOCK mul_add_x16
  .rept 16
  mul  a4, s4, s5
  addi a5, s5, 1
  .endr
ENDBLOCK

BLOCK mul_add_add_x11
  .rept 11
  mul  a4, s4, s5
  addi a5, s5, 1
  addi a7, s5, 1
  .endr
ENDBLOCK

BLOCK ld_add_x16
  .rept 16
  ld   a4, 0(s10)
  addi a5, s5, 1
  .endr
ENDBLOCK

BLOCK ld_mul_x16
  .rept 16
  ld   a4, 0(s10)
  mul  a5, s4, s5
  .endr
ENDBLOCK

BLOCK ld_sd_x16
  .set off, 0
  .rept 16
  ld   a4, 0(s10)
  sd   s4, off(s8)
  .set off, off + 8
  .endr
ENDBLOCK

BLOCK div_add10_x4
  divu a4, s2, s3
  REPEAT 10, addi a5, s5, 1
  divu a6, s1, s3
  REPEAT 10, addi a5, s5, 1
  divu a7, s2, s3
  REPEAT 10, addi a5, s5, 1
  divu t3, s1, s3
  REPEAT 10, addi a5, s5, 1
ENDBLOCK

BLOCK div_mul_x4
  divu a4, s2, s3
  mul  t4, s4, s5
  divu a6, s1, s3
  mul  t5, s4, s5
  divu a7, s2, s3
  mul  t4, s4, s5
  divu t3, s1, s3
  mul  t5, s4, s5
ENDBLOCK

BLOCK mul_ld_add_x11
  .rept 11
  mul  a4, s4, s5
  ld   a5, 0(s10)
  addi a7, s5, 1
  .endr
ENDBLOCK

# ---------------------------------------------------------------------------- data
  .data
  .balign 64
data0:  .space 256
hitbuf: .dword 7, 8, 9, 10, 0, 0, 0, 0
        .space 192
miss0:  .dword 11
        .space 248
