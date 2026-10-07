# ============================================================================
# p5_sys02_timer_irq : CLINT 타이머 인터럽트 / 소프트웨어 인터럽트 / WFI
#
#  CLINT (UM 9장) : base = 0x40_0400_0000 (SoC 의 pad_cpu_apb_base + 0x400_0000)
#    MSIP0     +0x0000  bit0=1 -> mip.MSIP (machine software interrupt, cause 3)
#    MTIMECMP  +0x4000(L) / +0x4004(H) : mtime >= mtimecmp -> mip.MTIP (cause 7)
#    mtime 은 MMIO 가 아니라 time CSR(rdtime) 으로 읽는다.
#  인터럽트가 실제로 받아들여지려면  mip.X && mie.X && (mstatus.MIE || 현재 모드 < M)
#
#  MARK 1 : time 과 mcycle 의 증가 속도 비교
#  MARK 2 : mtimecmp = now + 300 설정 후 WFI -> 타이머 인터럽트로 깨어남
#  MARK 3 : MSIP0 = 1 -> 소프트웨어 인터럽트
#  MARK 4 : mstatus.MIE=0 상태에서 MSIP0 = 1 -> pending 만 되고 받아들여지지 않음 -> MIE=1 순간 진입
#  M handler : s8=mcause s9=mepc s10=진입 time s11=진입 mcycle, s7=인터럽트 횟수
# GTKW: rt cp0
# ============================================================================
#include "study.h"

  .text
  .option norvc
  .globl main
main:
  li   s7, 0
  # ------------------------------------------------ MARK 1 : time vs mcycle
  MARK(1)
  rdtime s0
  csrr s1, mcycle
  li   t1, 200
1:
  addi t1, t1, -1
  bnez t1, 1b
  rdtime s2
  csrr s3, mcycle
  sub  s2, s2, s0
  sub  s3, s3, s1
  MARK(0)
  REPORT "time_ticks", s2
  REPORT "mcycle_ticks", s3

  # ------------------------------------------------ MARK 2 : timer interrupt + WFI
  li   t0, (1 << 7)              # mie.MTIE
  csrs mie, t0
  csrsi mstatus, 8               # mstatus.MIE
  li   t0, CLINT_MTIMECMPH       # 64-bit 비교값은 H 를 먼저 최대로 -> L -> H 순서로 쓴다
  li   t1, -1
  sw   t1, 0(t0)
  rdtime a0
  addi a0, a0, 300               # (CLINT 레지스터 쓰기가 도착하는 시간보다 넉넉히)
  mv   s6, a0                    # 목표 time
  li   t0, CLINT_MTIMECMPL
  sw   a0, 0(t0)
  srli a1, a0, 32
  li   t0, CLINT_MTIMECMPH
  sw   a1, 0(t0)
  MARK(2)
  csrr s5, mcycle
site_wfi:
  wfi                            # 인터럽트가 pending 될 때까지 대기 (저전력)
  MARK(0)
  sub  s10, s10, s6              # 진입 time - 목표 time
  sub  s11, s11, s5              # WFI ~ handler 진입 사이클
  la   t1, site_wfi
  sub  s9, s9, t1                # mepc - wfi 주소
  REPORT "timer_mcause", s8
  REPORT "timer_mepc_minus_wfi", s9
  REPORT "timer_entry_time_minus_target", s10
  REPORT "wfi_to_handler_cycles", s11

  # ------------------------------------------------ MARK 3 : software interrupt
  li   t0, (1 << 3)              # mie.MSIE
  csrs mie, t0
  MARK(3)
  li   t0, CLINT_MSIP0
  li   t1, 1
  sw   t1, 0(t0)
  .rept 16
  nop
  .endr
  MARK(0)
  REPORT "swi_mcause", s8
  REPORT "irq_count_after_swi", s7

  # ------------------------------------------------ MARK 4 : MIE=0 -> pending only
  csrci mstatus, 8
  MARK(4)
  li   t0, CLINT_MSIP0
  li   t1, 1
  sw   t1, 0(t0)
  .rept 16
  nop
  .endr
  csrr s4, mip
  mv   s3, s7                    # 이 시점까지 인터럽트 횟수 (늘지 않아야 함)
  csrsi mstatus, 8               # 여기서 바로 진입
  nop
  nop
  MARK(0)
  andi s4, s4, 8
  srli s4, s4, 3
  REPORT "mip_MSIP_while_MIE0", s4
  REPORT "irq_count_while_MIE0", s3
  REPORT "irq_count_after_MIE1", s7
  csrci mstatus, 8
  csrw mie, zero
  j    pass

# ----------------------------------------------------------------------------
  .balign 64
  .globl trap_handler
trap_handler:
  rdtime s10
  csrr s11, mcycle
  csrr s8, mcause
  csrr s9, mepc
  bgez s8, __default_trap        # 동기 예외면 실패 (mcause[63]=1 이 인터럽트)
  addi s7, s7, 1
  andi t3, s8, 0xff
  li   t4, 7
  beq  t3, t4, 1f
  li   t4, 3
  beq  t3, t4, 2f
  j    __default_trap
1:                               # timer : mtimecmp 를 최대로 돌려 pending 해제
  li   t3, CLINT_MTIMECMPH
  li   t4, -1
  sw   t4, 0(t3)
  li   t3, CLINT_MTIMECMPL
  sw   t4, 0(t3)
3:
  csrr t4, mip                   # 해제(쓰기)가 CLINT 에 도착하고 mip 에 반영될 때까지 기다린다.
  andi t4, t4, (1 << 7)          # 기다리지 않고 mret 하면 같은 인터럽트에 한 번 더 들어올 수 있다.
  bnez t4, 3b
  mret
2:                               # software : MSIP0 = 0 으로 해제
  li   t3, CLINT_MSIP0
  sw   zero, 0(t3)
4:
  csrr t4, mip
  andi t4, t4, (1 << 3)
  bnez t4, 4b
  mret
