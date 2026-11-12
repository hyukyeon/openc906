# ============================================================================
# p6_fp01_latency : FPU latency / throughput, fflags 예외 비트, mstatus.FS
#
#  MARK 1 : fadd.d  의존 체인 x16  vs  MARK 2 : 독립 x16       -> latency / throughput
#  MARK 3 : fmul.d  의존 체인 x16       MARK 4 : fmadd.d 의존 체인 x16
#  MARK 5 : fdiv.d / fsqrt.d / fdiv.s 한 번씩 (FDSU, 반복형) - 결과를 바로 정수 레지스터로 옮겨 기다린다
#  MARK 6 : fflags - 0 으로 나누기(DZ), 0/0(NV), 1/3(NX), 큰 수 곱(OF), 작은 수 곱(UF)
#  MARK 7 : mstatus.FS - FP 명령 뒤 Dirty(3). FS = Off(0) 로 끄면 FP 명령이 illegal instruction(2)
#
#  사이클 = TIC/TOC 차이. 빈 TIC/TOC 를 baseline 으로 함께 보고한다.
#  trap_handler 는 s8..s11 만 쓴다 (s8 = mcause, s9 = mepc, s10 = mtval, s11 = 진입 횟수)
# GTKW: fp ex rt
# ZOOM: mark
# ============================================================================
#include "study.h"

.macro LOADD freg, sym
  la   t0, \sym
  fld  \freg, 0(t0)
.endm

  .text
  .globl main
main:
  li   s11, 0
  LOADD f2, c_one
  LOADD f3, c_two
  LOADD f4, c_three
  LOADD f5, c_big
  LOADD f6, c_tiny
  fmv.d.x f7, zero                # 0.0

  TIC(s0)
  TOC(s0)
  REPORT "baseline_tictoc", s0

  # ---------------------------------------------------------------- MARK 1 / 2 : fadd.d
  fmv.d f1, f2
  MARK(1)
  TIC(s0)
  REPEAT 16, fadd.d f1, f1, f2
  fmv.x.d t1, f1
  TOC(s0)
  MARK(0)
  REPORT "m1_fadd_d_chain16", s0

  MARK(2)
  TIC(s0)
  .rept 4
  fadd.d f10, f2, f3
  fadd.d f11, f2, f3
  fadd.d f12, f2, f3
  fadd.d f13, f2, f3
  .endr
  fmv.x.d t1, f13
  TOC(s0)
  MARK(0)
  REPORT "m2_fadd_d_indep16", s0

  # ---------------------------------------------------------------- MARK 3 / 4 : fmul.d, fmadd.d
  fmv.d f1, f2
  MARK(3)
  TIC(s0)
  REPEAT 16, fmul.d f1, f1, f2
  fmv.x.d t1, f1
  TOC(s0)
  MARK(0)
  REPORT "m3_fmul_d_chain16", s0

  fmv.d f1, f2
  MARK(4)
  TIC(s0)
  REPEAT 16, fmadd.d f1, f1, f2, f2
  fmv.x.d t1, f1
  TOC(s0)
  MARK(0)
  REPORT "m4_fmadd_d_chain16", s0

  # ---------------------------------------------------------------- MARK 5 : FDSU
  MARK(5)
  TIC(s0)
  fdiv.d  f1, f2, f4              # 1/3
  fmv.x.d t1, f1
  TOC(s0)
  REPORT "m5_fdiv_d_1_3", s0
  TIC(s0)
  fdiv.d  f1, f3, f3              # 2/2
  fmv.x.d t1, f1
  TOC(s0)
  REPORT "m5_fdiv_d_2_2", s0
  TIC(s0)
  fsqrt.d f1, f3                  # sqrt(2)
  fmv.x.d t1, f1
  TOC(s0)
  REPORT "m5_fsqrt_d_2", s0
  fcvt.s.d f8, f2                 # 1.0f
  fcvt.s.d f9, f4                 # 3.0f
  TIC(s0)
  fdiv.s  f1, f8, f9              # 1/3 (단정밀도)
  fmv.x.w t1, f1
  TOC(s0)
  MARK(0)
  REPORT "m5_fdiv_s_1_3", s0

  # ---------------------------------------------------------------- MARK 6 : fflags
  MARK(6)
  fsflags zero
  fdiv.d  f1, f2, f7              # 1/0
  frflags s1
  fsflags zero
  fdiv.d  f1, f7, f7              # 0/0
  frflags s2
  fsflags zero
  fdiv.d  f1, f2, f4              # 1/3
  frflags s3
  fsflags zero
  fmul.d  f1, f5, f5              # 1e300 * 1e300
  frflags s4
  fsflags zero
  fmul.d  f1, f6, f6              # 1e-300 * 1e-300
  frflags s5
  MARK(0)
  EXPECT s1, 0x08                 # DZ
  EXPECT s2, 0x10                 # NV
  EXPECT s3, 0x01                 # NX
  EXPECT s4, 0x05                 # OF | NX
  EXPECT s5, 0x03                 # UF | NX
  REPORT "fflags_1_div_0", s1
  REPORT "fflags_0_div_0", s2
  REPORT "fflags_1_div_3", s3
  REPORT "fflags_big_mul", s4
  REPORT "fflags_tiny_mul", s5

  # ---------------------------------------------------------------- MARK 7 : mstatus.FS
  MARK(7)
  csrr t1, mstatus
  srli s1, t1, 13
  andi s1, s1, 3                  # FS : FP 명령을 썼으니 Dirty(3)
  li   t0, (3 << 13)
  csrc mstatus, t0                # FS = Off
  fadd.d f1, f2, f2               # -> illegal instruction
  li   t0, (1 << 13)
  csrs mstatus, t0                # FS = Initial
  csrr t1, mstatus
  srli s2, t1, 13
  andi s2, s2, 3                  # Initial(1)
  fadd.d f1, f2, f2
  csrr t1, mstatus
  srli s3, t1, 13
  andi s3, s3, 3                  # 다시 Dirty(3)
  MARK(0)
  EXPECT s1, 3
  EXPECT s8, 2                    # mcause = illegal instruction
  EXPECT s11, 1
  EXPECT s2, 1
  EXPECT s3, 3
  REPORT "fs_after_fp_ops", s1
  REPORT "fs_off_mcause", s8
  REPORT "fs_off_mtval", s10
  REPORT "fs_after_set_initial", s2
  REPORT "fs_after_one_fadd", s3
  j    pass

# ----------------------------------------------------------------------------
  .balign 64
  .globl trap_handler
trap_handler:
  csrr s8, mcause
  csrr s9, mepc
  csrr s10, mtval
  addi s11, s11, 1
  addi t3, s9, 4                  # fadd.d 는 32-bit
  csrw mepc, t3
  mret

  .data
  .balign 8
c_one:   .double 1.0
c_two:   .double 2.0
c_three: .double 3.0
c_big:   .double 1.0e300
c_tiny:  .double 1.0e-300
