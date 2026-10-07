# ============================================================================
# p5_sys06_wfi_flag : 인터럽트 플래그 + WFI 대기 루프
#
#    volatile uint32_t int_flag;          // INT_FLAG_ADDR (common/study.h), probe 가 파형에 int_flag 로 보여 준다
#    void m_mei(void) { id = claim(); if (id == 35) int_flag = 1; 장치 해제; complete(id); }
#    ...
#    int_flag = 0;
#    while (!int_flag) { wfi; }           // 어셈블리로는 아래 4 줄 (lw / bnez / wfi / j)
#
#  WFI : mip & mie 에 1 인 비트가 생길 때까지 잔다. mstatus.MIE 는 깨어나는 조건과 무관하다.
#        깨어나면 WFI 가 retire 하고, 인터럽트가 그 retire 에 붙어 trap 이 된다 -> mepc = wfi + 4 (j, 아직 실행 전).
#        핸들러가 int_flag = 1 로 만들고 mret 하면 j -> lw 가 1 을 읽어 루프를 빠져나간다.
#        mstatus.MIE = 0 이면 깨어나기만 하고 핸들러에 가지 않아 int_flag 가 안 바뀐다 -> 다시 잠든다 (무한 대기)
#  주의 (경쟁) : lw 와 wfi 사이에 인터럽트가 처리되면 int_flag = 1 인데 wfi 로 잠든다. 다음 인터럽트까지 못 깬다.
#        이 테스트는 인터럽트가 잠든 뒤(MARK 1, 2) 또는 루프 전(MARK 3)에 오도록 시간을 맞췄다.
#
#  MARK 1 : 루프에 들어가 잠든 뒤 ID 35 인터럽트 -> 핸들러가 int_flag = 1 -> 루프 탈출 (wfi 1 번)
#  MARK 2 : 먼저 ID 36 (플래그와 무관한 인터럽트)이 깨움 -> int_flag 는 0 이라 다시 wfi
#           -> 나중에 ID 35 -> 탈출. "if (!int_flag) wfi;" 한 번이 아니라 while 이어야 하는 이유
#  MARK 3 : 루프에 들어가기 전에 이미 인터럽트가 처리됨 -> 첫 검사에서 바로 탈출, wfi 를 실행하지 않음
#
#  레지스터 : main = s0..s4 / 핸들러가 기록 = s5 횟수, s6 마지막 claim ID, s7 ID 이력 (s7 = s7<<8 | id),
#             s8 첫 mepc, s9 마지막 mepc, s10 int_flag 를 1 로 만든 mcycle, s11 마지막 진입 mcycle
# GTKW: wfi irq trap
# ZOOM: mark  (웹 뷰어 : trap 주변이 아니라 MARK 구간 전체 = 잠듦 -> 깨어남 -> 핸들러 -> 탈출)
# ============================================================================
#include "study.h"

#define MSTATUS_MIE   (1 << 3)
#define MIE_MEIE      (1 << 11)
#define TB_IRQ_BITS   ((1 << (TB_IRQ0_ID - 32)) | (1 << (TB_IRQ1_ID - 32)))

/* while (!int_flag) { wfi; }   (s1 = &int_flag). 라벨 \name_wfi 는 wfi 명령 주소 */
.macro WFI_LOOP name
\name:
  lw   t0, 0(s1)                 # int_flag 를 매번 메모리에서 다시 읽는다 (volatile)
  bnez t0, \name\()_exit
\name\()_wfi:
  wfi
  j    \name
\name\()_exit:
.endm

/* 핸들러 기록 초기화 + int_flag = 0 */
.macro RESET_STATE
  li   s5, 0
  li   s6, 0
  li   s7, 0
  li   s8, 0
  li   s9, 0
  li   s10, 0
  li   s11, 0
  sw   zero, 0(s1)
.endm

  .text
  .option norvc
  .globl main
main:
  # ------------------------------------------------ 공통 설정 (M)
  la   t0, m_vectors
  ori  t0, t0, 1                 # vectored : MEI -> m_vectors + 4*11
  csrw mtvec, t0
  csrw mideleg, zero
  li   t1, 1
  li   t0, PLIC_PRIO(TB_IRQ0_ID) # ID 35, 36 우선순위 1
  sw   t1, 0(t0)
  li   t0, PLIC_PRIO(TB_IRQ1_ID)
  sw   t1, 0(t0)
  li   t0, PLIC_H0_MTH
  sw   zero, 0(t0)
  li   t0, PLIC_H0_MIE1          # 두 ID 모두 M 컨텍스트에서 enable
  li   t1, TB_IRQ_BITS
  sw   t1, 0(t0)
  li   t0, MIE_MEIE
  csrs mie, t0
  csrsi mstatus, MSTATUS_MIE
  li   s1, INT_FLAG_ADDR
  li   s2, TBDEV_BASE

  # ------------------------------------------------ MARK 1 : 잠든 뒤 인터럽트 -> 플래그 -> 탈출
  RESET_STATE
  li   t1, 300                   # 300 사이클 뒤 선 0 (ID 35). 루프가 먼저 wfi 에서 잠들 만큼 넉넉히
  MARK(1)
  sd   t1, TBDEV_IRQ0_SET(s2)
  csrr s3, mcycle
  WFI_LOOP loop1
  csrr s4, mcycle
  MARK(0)
  lw   s0, 0(s1)
  REPORT "m1_int_flag_after_loop", s0
  REPORT "m1_irq_count", s5
  REPORT "m1_id_history", s7
  la   t1, loop1_wfi
  sub  t1, s8, t1
  REPORT "m1_mepc_minus_wfi", t1
  sub  t1, s10, s11
  REPORT "m1_handler_entry_to_flag_set_mcycle", t1
  sub  t1, s4, s10
  REPORT "m1_flag_set_to_loop_exit_mcycle", t1
  EXPECT s0, 1
  EXPECT s5, 1
  EXPECT s7, TB_IRQ0_ID
  la   t1, loop1_wfi+4
  bne  s8, t1, fail

  # ------------------------------------------------ MARK 2 : 다른 인터럽트가 먼저 깨움 -> 다시 wfi
  RESET_STATE
  li   t1, 200                   # 선 1 (ID 36) : 200 사이클 뒤. 핸들러는 플래그를 건드리지 않는다
  li   t2, 600                   # 선 0 (ID 35) : 600 사이클 뒤
  MARK(2)
  sd   t1, TBDEV_IRQ1_SET(s2)
  sd   t2, TBDEV_IRQ0_SET(s2)
  csrr s3, mcycle
  WFI_LOOP loop2
  csrr s4, mcycle
  MARK(0)
  lw   s0, 0(s1)
  REPORT "m2_int_flag_after_loop", s0
  REPORT "m2_irq_count", s5
  REPORT "m2_id_history", s7
  la   t1, loop2_wfi
  sub  t1, s8, t1
  REPORT "m2_first_mepc_minus_wfi", t1
  la   t1, loop2_wfi
  sub  t1, s9, t1
  REPORT "m2_last_mepc_minus_wfi", t1
  sub  t1, s10, s11
  REPORT "m2_handler_entry_to_flag_set_mcycle", t1
  EXPECT s0, 1
  EXPECT s5, 2
  EXPECT s7, (TB_IRQ1_ID << 8) | TB_IRQ0_ID
  la   t1, loop2_wfi+4
  bne  s8, t1, fail
  bne  s9, t1, fail

  # ------------------------------------------------ MARK 3 : 루프 전에 이미 처리됨 -> wfi 없이 탈출
  RESET_STATE
  li   t1, 1
  MARK(3)
  sd   t1, TBDEV_IRQ0_SET(s2)
  .rept 120                      # 이 사이에 인터럽트를 받아 int_flag = 1
  addi a5, a5, 1
  .endr
  csrr s3, mcycle
  WFI_LOOP loop3
  csrr s4, mcycle
  MARK(0)
  lw   s0, 0(s1)
  REPORT "m3_int_flag_after_loop", s0
  REPORT "m3_irq_count", s5
  sub  t1, s4, s3
  REPORT "m3_loop_mcycle", t1
  EXPECT s0, 1
  EXPECT s5, 1

  csrci mstatus, MSTATUS_MIE
  csrw mie, zero
  li   t0, PLIC_H0_MIE1
  sw   zero, 0(t0)
  j    pass

# ============================================================================ M 벡터 테이블
  .balign 64
m_vectors:
  j    __default_trap            #  0 : 예외
  .rept 10
  j    __default_trap            #  1 ~ 10
  .endr
  j    m_mei                     # 11 : MEI

# ---------------------------------------------------------------- M 외부 인터럽트 핸들러
m_mei:
  addi sp, sp, -32
  sd   t0, 0(sp)
  sd   t1, 8(sp)
  sd   t2, 16(sp)
  li   t2, 1                     # int_flag 에 쓸 값 (store 보다 먼저 준비 -> probe 가 DC 단계에서 읽는다)
  csrr t1, mepc                  # (학습용 기록)
  bnez s5, 1f
  mv   s8, t1                    # 첫 mepc
1:
  csrr s11, mcycle               # 진입 mcycle
  mv   s9, t1                    # 마지막 mepc
  addi s5, s5, 1
  li   t0, PLIC_H0_MCLAIM        # claim
  lw   s6, 0(t0)
  slli s7, s7, 8
  or   s7, s7, s6
  li   t1, TB_IRQ0_ID
  bne  s6, t1, 2f
  # ---- ID 35 : 기다리던 이벤트
  sw   t2, 0(s1)                 # int_flag = 1   (메인 루프가 볼 수 있는 유일한 신호)
  csrr s10, mcycle
  sd   zero, TBDEV_IRQ0_CLR(s2)  # 장치 해제 (level 선을 내린다)
  j    3f
2:
  li   t1, TB_IRQ1_ID
  bne  s6, t1, 4f
  # ---- ID 36 : 다른 장치. 플래그는 그대로
  sd   zero, TBDEV_IRQ1_CLR(s2)
3:
  sw   s6, 0(t0)                 # complete (장치 해제 뒤에)
4:
  ld   t2, 16(sp)
  ld   t1, 8(sp)
  ld   t0, 0(sp)
  addi sp, sp, 32
  mret                           # PC <- mepc (= wfi 다음의 j) -> lw 가 int_flag 를 다시 읽는다
