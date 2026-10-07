# ============================================================================
# p3_be04_trap : 동기 예외(trap) 의 진입/복귀 - precise exception
#
#  예외는 RTU 가 retire 시점에 처리한다: 예외 명령 이후 명령은 모두 flush,
#  mepc/mcause/mtval/mstatus 갱신, PC <- mtvec. mret 으로 mepc 로 복귀.
#
#  MARK 1 : ecall (M-mode)           mcause=11
#  MARK 2 : 불법 명령 (읽기전용 CSR cycle 에 쓰기, 'unimp')   mcause=2, mtval=명령 인코딩?
#  MARK 3 : ebreak                   mcause=3
#  MARK 4 : misaligned load, MXSTATUS.MM=1 (HW 처리, 예외 없음) - 사이클 비교
#  MARK 5 : misaligned load, MXSTATUS.MM=0                         mcause=4, mtval=주소
#  MARK 6 : 정렬된 load (기준)
#  보고: 각 trap 의 mcause/mepc 오프셋/mtval, trap 진입까지 사이클, 왕복 사이클(warm)
#
#  trap_handler 는 s8..s11 만 사용 (s8=mcause s9=mepc s10=mtval s11=진입 mcycle)
# GTKW: ex rt cp0
# ============================================================================
#include "study.h"

  .text
  .option norvc
  .globl main
main:
  # ------------------------------------------------ MARK 1 : ecall (2 회 실행, 두 번째 = warm)
  li   s6, 2
1:
  MARK(1)
  TIC(s0)
  mv   s7, s0
site_ecall:
  ecall
  TOC(s0)
  MARK(0)
  addi s6, s6, -1
  bnez s6, 1b
  la   t1, site_ecall
  sub  s9, s9, t1                # mepc - 예외 명령 주소 (0 이어야 함)
  sub  s11, s11, s7              # TIC ~ handler 진입
  REPORT "ecall_mcause", s8
  REPORT "ecall_mepc_minus_site", s9
  REPORT "ecall_entry_cycles", s11
  REPORT "ecall_roundtrip_cycles", s0

  # ------------------------------------------------ MARK 2 : illegal instruction
  MARK(2)
site_illegal:
  unimp                          # = csrrw x0, cycle, x0 (읽기전용 CSR 쓰기 -> illegal)
  MARK(0)
  la   t1, site_illegal
  sub  s9, s9, t1
  REPORT "illegal_mcause", s8
  REPORT "illegal_mepc_minus_site", s9
  REPORT "illegal_mtval", s10
  la   t1, site_illegal
  lwu  t2, 0(t1)
  REPORT "illegal_inst_encoding", t2

  # ------------------------------------------------ MARK 3 : ebreak
  MARK(3)
site_ebreak:
  ebreak
  MARK(0)
  la   t1, site_ebreak
  sub  s9, s9, t1
  REPORT "ebreak_mcause", s8
  REPORT "ebreak_mepc_minus_site", s9
  REPORT "ebreak_mtval", s10

  # ------------------------------------------------ MARK 4/5/6 : misaligned load
  la   s5, buf
  ld   a4, 0(s5)                 # warm
  ld   a4, 8(s5)
  addi s6, s5, 3                 # 8B load 를 +3 에서 -> 8B 경계를 걸침
  li   s8, 0

  li   s7, 2                     # 2 회 실행, 두 번째(warm) 값을 보고
1:
  MARK(4)                        # MM=1 (reset 기본값) : 하드웨어가 처리
  TIC(s0)
  ld   a4, 0(s6)
  addi a5, a4, 0
  TOC(s0)
  MARK(0)
  addi s7, s7, -1
  bnez s7, 1b
  REPORT "misaligned_ld_mm1_cycles", s0
  REPORT "misaligned_ld_mm1_trap_cause", s8

  li   t1, (1 << 15)             # MXSTATUS.MM = 0
  csrc CSR_MXSTATUS, t1
  MARK(5)
site_misld:
  ld   a4, 0(s6)                 # -> load address misaligned 예외
  MARK(0)
  li   t1, (1 << 15)
  csrs CSR_MXSTATUS, t1
  sub  s10, s10, s5              # mtval - buf (3 이어야 함)
  REPORT "misaligned_ld_mm0_mcause", s8
  REPORT "misaligned_ld_mm0_mtval_minus_buf", s10

  li   s7, 2
1:
  MARK(6)
  TIC(s0)
  ld   a4, 0(s5)
  addi a5, a4, 0
  TOC(s0)
  MARK(0)
  addi s7, s7, -1
  bnez s7, 1b
  REPORT "aligned_ld_cycles", s0
  j    pass

# ----------------------------------------------------------------------------
# trap_handler : 원인 기록 후 예외 명령을 건너뛰고(mepc+4) 복귀
# ----------------------------------------------------------------------------
  .balign 64
  .globl trap_handler
trap_handler:
  csrr s11, mcycle
  csrr s8, mcause
  csrr s9, mepc
  csrr s10, mtval
  addi t3, s9, 4                 # 이 파일의 예외 명령은 모두 32-bit (norvc)
  csrw mepc, t3
  mret

  .data
  .balign 64
buf: .dword 0x1122334455667788, 0x99aabbccddeeff00
