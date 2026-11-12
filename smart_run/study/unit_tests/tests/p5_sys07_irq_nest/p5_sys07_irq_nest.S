# ============================================================================
# p5_sys07_irq_nest : M 모드 인터럽트 3 개의 우선순위, 중첩(nesting)
#
#  MARK 1 : mstatus.MIE = 0 인 동안 MEI(PLIC ID 35), MSI(CLINT MSIP0), MTI(mtimecmp = 0) 를 모두 pending
#           -> MIE = 1 -> 우선순위대로 MEI, MSI, MTI 가 하나씩 처리된다 (aq_rtu_int.v : MEI > MSI > MTI)
#  MARK 2 : 중첩 허용 - MTI 핸들러가 mepc/mstatus 를 스택에 저장하고 MIE 를 다시 켠 뒤 MSIP0 = 1
#           -> MTI 핸들러 안으로 MSI 가 끼어든다 : MTI 시작, MSI 시작, MSI 끝, MTI 끝
#  MARK 3 : 비교 - 같은 MTI 핸들러가 MIE 를 켜지 않으면 MSI 는 MTI 가 mret 한 뒤에 들어간다
#
#  핸들러는 들어올 때 mcause 번호(3/7/11), 나갈 때 번호 | 0x80 을 log_buf 에 1 바이트씩 남긴다.
#  main 은 log_buf 8 바이트를 ld 로 한 번에 읽어(little-endian) 기대값과 비교한다.
#  중첩의 핵심 : 다시 MIE 를 켜기 전에 mepc, mstatus(MPIE/MPP) 를 저장하고, mret 직전에 되돌린다.
# GTKW: irq rt
# ZOOM: mark
# ============================================================================
#include "study.h"

#define MSTATUS_MIE   (1 << 3)
#define MIE_MSIE      (1 << 3)
#define MIE_MTIE      (1 << 7)
#define MIE_MEIE      (1 << 11)
#define MIP_ALL3      ((1 << 3) | (1 << 7) | (1 << 11))
#define TB_IRQ0_BIT   (1 << (TB_IRQ0_ID - 32))

/* log_buf[log_idx++] = val (a0, a1 사용) */
.macro LOG val
  la   a0, log_idx
  lw   a1, 0(a0)
  addi a1, a1, 1
  sw   a1, 0(a0)
  la   a0, log_buf - 1
  add  a0, a0, a1
  li   a1, \val
  sb   a1, 0(a0)
.endm

.macro LOG_REG reg
  la   a0, log_idx
  lw   a1, 0(a0)
  addi a1, a1, 1
  sw   a1, 0(a0)
  la   a0, log_buf - 1
  add  a0, a0, a1
  sb   \reg, 0(a0)
.endm

.macro LOG_RESET
  la   t0, log_idx
  sw   zero, 0(t0)
  la   t0, log_buf
  sd   zero, 0(t0)
.endm

.macro TIMER_OFF                  # mtimecmp = 최대값 (H 먼저)
  li   t2, CLINT_MTIMECMPH
  li   t3, -1
  sw   t3, 0(t2)
  li   t2, CLINT_MTIMECMPL
  sw   t3, 0(t2)
.endm

.macro TIMER_NOW                  # mtimecmp = 0 -> 곧바로 MTIP
  li   t2, CLINT_MTIMECMPL
  sw   zero, 0(t2)
  li   t2, CLINT_MTIMECMPH
  sw   zero, 0(t2)
.endm

  .text
  .globl main
main:
  csrci mstatus, MSTATUS_MIE
  TIMER_OFF
  li   t0, PLIC_PRIO(TB_IRQ0_ID)
  li   t1, 1
  sw   t1, 0(t0)
  li   t0, PLIC_H0_MTH
  sw   zero, 0(t0)
  li   t0, PLIC_H0_MIE1
  li   t1, TB_IRQ0_BIT
  sw   t1, 0(t0)

  # ---------------------------------------------------------------- MARK 1 : 우선순위
  LOG_RESET
  la   t0, nest_mode
  sw   zero, 0(t0)
  li   t0, MIE_MEIE | MIE_MSIE | MIE_MTIE
  csrw mie, t0
  li   t0, TBDEV_BASE
  li   t1, 1
  sd   t1, TBDEV_IRQ0_SET(t0)     # 외부 인터럽트 선 0 -> 1
  li   t2, CLINT_MSIP0
  li   t3, 1
  sw   t3, 0(t2)                  # MSIP0 = 1
  TIMER_NOW                       # MTIP
  li   t1, MIP_ALL3
1:
  csrr t0, mip
  and  t0, t0, t1
  bne  t0, t1, 1b                 # 세 개가 다 pending 될 때까지
  MARK(1)
  csrsi mstatus, MSTATUS_MIE      # 여기서 한꺼번에 풀린다
  nop
  nop
  MARK(0)
  csrci mstatus, MSTATUS_MIE
  la   t0, log_buf
  ld   s1, 0(t0)
  li   t1, 0x0000870783038b0b     # 0b 8b 03 83 07 87 : MEI, MSI, MTI 순서
  bne  s1, t1, fail
  REPORT "m1_log_hex_as_dec", s1

  # ---------------------------------------------------------------- MARK 2 : 중첩
  LOG_RESET
  la   t0, nest_mode
  li   t1, 1
  sw   t1, 0(t0)
  li   t0, MIE_MSIE | MIE_MTIE
  csrw mie, t0
  csrsi mstatus, MSTATUS_MIE
  MARK(2)
  TIMER_NOW
  li   t3, 60
2:
  addi t3, t3, -1
  bnez t3, 2b
  MARK(0)
  csrci mstatus, MSTATUS_MIE
  la   t0, log_buf
  ld   s2, 0(t0)
  li   t1, 0x87830307             # 07 03 83 87 : MTI 안에서 MSI 가 시작하고 끝난다
  bne  s2, t1, fail
  REPORT "m2_log_hex_as_dec", s2

  # ---------------------------------------------------------------- MARK 3 : 중첩 없음
  LOG_RESET
  la   t0, nest_mode
  li   t1, 2
  sw   t1, 0(t0)
  csrsi mstatus, MSTATUS_MIE
  MARK(3)
  TIMER_NOW
  li   t3, 60
3:
  addi t3, t3, -1
  bnez t3, 3b
  MARK(0)
  csrci mstatus, MSTATUS_MIE
  la   t0, log_buf
  ld   s3, 0(t0)
  li   t1, 0x83038707             # 07 87 03 83 : MTI 가 끝난 뒤에 MSI
  bne  s3, t1, fail
  REPORT "m3_log_hex_as_dec", s3

  csrw mie, zero
  j    pass

# ----------------------------------------------------------------------------
# trap_handler : 재진입 가능 (스택에 t0-t3, a0-a1, mepc, mstatus 저장)
# ----------------------------------------------------------------------------
  .balign 64
  .globl trap_handler
trap_handler:
  addi sp, sp, -64
  sd   t0, 0(sp)
  sd   t1, 8(sp)
  sd   t2, 16(sp)
  sd   t3, 24(sp)
  sd   a0, 32(sp)
  sd   a1, 40(sp)
  csrr t0, mepc
  sd   t0, 48(sp)
  csrr t0, mstatus
  sd   t0, 56(sp)
  csrr t1, mcause
  bgez t1, fail                   # 예외는 기대하지 않는다
  andi t1, t1, 0x3f
  LOG_REG t1
  li   t0, 7
  beq  t1, t0, h_mti
  li   t0, 3
  beq  t1, t0, h_msi
  li   t0, 11
  beq  t1, t0, h_mei
  j    fail

h_mti:
  TIMER_OFF
  la   t2, nest_mode
  lw   t3, 0(t2)
  beqz t3, h_done
  li   t2, CLINT_MSIP0
  li   t0, 1
  sw   t0, 0(t2)                  # MSI 를 건다
  li   t0, 1
  bne  t3, t0, h_mti_wait         # nest_mode 2 : MIE 를 켜지 않는다
  csrsi mstatus, MSTATUS_MIE      # nest_mode 1 : 중첩 허용 -> 여기서 MSI 가 끼어든다
h_mti_wait:
  li   t3, 30
4:
  addi t3, t3, -1
  bnez t3, 4b
  csrci mstatus, MSTATUS_MIE
  j    h_done

h_msi:
  li   t2, CLINT_MSIP0
  sw   zero, 0(t2)
  j    h_done

h_mei:
  li   t2, PLIC_H0_MCLAIM
  lw   t3, 0(t2)                  # claim
  li   t0, TBDEV_BASE
  sd   zero, TBDEV_IRQ0_CLR(t0)   # 장치 쪽 원인 해제 (complete 보다 먼저)
  sw   t3, 0(t2)                  # complete

h_done:
  ori  t1, t1, 0x80
  LOG_REG t1
  ld   t0, 48(sp)
  csrw mepc, t0
  ld   t0, 56(sp)
  csrw mstatus, t0                # MPIE/MPP 를 이 trap 이 들어올 때 값으로
  ld   t0, 0(sp)
  ld   t1, 8(sp)
  ld   t2, 16(sp)
  ld   t3, 24(sp)
  ld   a0, 32(sp)
  ld   a1, 40(sp)
  addi sp, sp, 64
  mret

  .data
  .balign 8
log_buf:   .dword 0
log_idx:   .word 0
nest_mode: .word 0
