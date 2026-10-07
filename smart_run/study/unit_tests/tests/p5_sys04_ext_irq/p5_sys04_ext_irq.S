# ============================================================================
# p5_sys04_ext_irq : 외부(HW) 인터럽트 진입 해부 - M 모드 vs S 모드 (TB 장치 -> PLIC -> 코어)
#
#  TB 장치 (tb/study_tbdev.v) : 테스트벤치가 SoC 외부 인터럽트 선을 구동한다. 선 0 = PLIC ID 35 (level)
#    store 로 제어 : TBDEV_IRQ0_SET = N -> N 사이클 뒤 선 0 이 1,  TBDEV_IRQ0_CLR -> 0 (장치 쪽 원인 해제)
#  PLIC (study.h) : 우선순위, 컨텍스트별 enable / threshold / claim-complete. M 컨텍스트 -> mip.MEIP,
#    S 컨텍스트 -> mip.SEIP
#  mtvec / stvec 은 vectored(MODE=1) : 인터럽트는 BASE + 4*cause 로, 예외는 BASE 로 간다
#
#  MARK 1 : M 모드 실행 중 MEI (mcause 11)          -> mtvec+0x2C, mepc/mstatus.MPIE/MPP 변화
#  MARK 2 : S 모드 실행 중 SEI, mideleg.SEI=1 (scause 9) -> stvec+0x24, 모드는 S 그대로 (S -> S)
#  MARK 3 : S 모드 실행 중 MEI, mstatus.MIE=0 이어도   -> M 으로 (하위 모드에서 M 인터럽트는 항상 켜짐)
#  MARK 4 : M 모드 실행 중 위임된 SEI 가 pending       -> M 에서는 받지 않음 -> S 로 내려가는 mret 에 붙어서 바로 받음
#           (C906: mret 이 retire 하는 사이클에 모드가 이미 S -> sepc = mret 의 다음 PC = s_part4, S 첫 명령은 실행 전)
#
#  레지스터 : main = s0..s4, a5 / 핸들러가 기록 = s5 횟수, s6 claim ID, s7 cause 이력 (s7 = s7<<8 | cause),
#             s8 cause, s9 epc, s10 status, s11 진입 cycle
# GTKW: irq trap
# ============================================================================
#include "study.h"

#define MSTATUS_MIE   (1 << 3)
#define MSTATUS_MPIE  (1 << 7)
#define MSTATUS_MPP   (3 << 11)
#define SSTATUS_SIE   (1 << 1)
#define MIE_SEIE      (1 << 9)
#define MIE_MEIE      (1 << 11)
#define TB_IRQ0_BIT   (1 << (TB_IRQ0_ID - 32))     /* PLIC enable 레지스터 (ID 32~63) 의 비트 */
#define BUSY_N        200

/* M -> S : MPP = S, mepc = label, mret */
.macro M_TO_S label
  li   t0, MSTATUS_MPP
  csrc mstatus, t0
  li   t0, (1 << 11)
  csrs mstatus, t0
  la   t0, \label
  csrw mepc, t0
  mret
.endm

/* S -> M : ecall (a7 = 0) 로 M 의 label 에서 계속 (m_sync 참고). S 는 mscratch(콘솔)를 못 써서 출력은 M 에서 한다 */
.macro S_TO_M label
  la   a0, \label
  li   a7, 0
  ecall
.endm

/* 인터럽트가 들어오기를 기다리는 일반 명령 블록. 인터럽트가 몇 번째 명령에서 끼어들든 a5 는 BUSY_N 이 되어야 한다 */
.macro BUSY label
\label:
  .rept BUSY_N
  addi a5, a5, 1
  .endr
.endm

  .text
  .option norvc                  # 벡터 테이블 엔트리가 4 바이트여야 한다
  .globl main
main:
  # ------------------------------------------------ 공통 설정 (M)
  la   t0, m_vectors
  ori  t0, t0, 1                 # MODE = 1 (vectored)
  csrw mtvec, t0
  la   t0, s_vectors
  ori  t0, t0, 1
  csrw stvec, t0
  li   t0, 7
  csrw mcounteren, t0            # S 핸들러가 rdcycle 할 수 있게
  csrw mideleg, zero
  csrw medeleg, zero
  li   t0, PLIC_PRIO(TB_IRQ0_ID) # ID 35 우선순위 1 (0 이면 꺼짐)
  li   t1, 1
  sw   t1, 0(t0)
  li   t0, PLIC_H0_MTH           # threshold 0 : 우선순위 > 0 이면 통과
  sw   zero, 0(t0)
  li   t0, PLIC_H0_STH
  sw   zero, 0(t0)
  li   s5, 0

  # ------------------------------------------------ MARK 1 : M 모드 외부 인터럽트
  li   t0, PLIC_H0_MIE1          # PLIC: ID 35 를 M 컨텍스트에서 enable
  li   t1, TB_IRQ0_BIT
  sw   t1, 0(t0)
  li   t0, MIE_MEIE              # mie.MEIE : M 외부 인터럽트 개별 enable
  csrs mie, t0
  csrsi mstatus, MSTATUS_MIE     # mstatus.MIE : M 모드 전역 enable
  li   s7, 0
  li   a5, 0
  li   t0, TBDEV_BASE
  li   t1, 40
  MARK(1)
  sd   t1, TBDEV_IRQ0_SET(t0)    # 40 사이클 뒤에 외부 인터럽트 선이 1 이 된다
  BUSY m_busy1
  MARK(0)
  mv   s0, a5
  REPORT "m1_irq_count", s5
  REPORT "m1_cause_history", s7
  REPORT "m1_mcause", s8
  la   t1, m_busy1
  sub  t1, s9, t1
  srli t1, t1, 2
  REPORT "m1_mepc_index_in_busy", t1
  srli t1, s10, 11
  andi t1, t1, 3
  REPORT "m1_mstatus_MPP_at_entry(3=M)", t1
  srli t1, s10, 7
  andi t1, t1, 1
  REPORT "m1_mstatus_MPIE_at_entry", t1
  andi t1, s10, MSTATUS_MIE
  srli t1, t1, 3
  REPORT "m1_mstatus_MIE_at_entry", t1
  REPORT "m1_claim_id", s6
  REPORT "m1_busy_count", s0
  EXPECT s5, 1
  EXPECT s6, TB_IRQ0_ID
  EXPECT s0, BUSY_N

  # ------------------------------------------------ MARK 2 : S 모드 외부 인터럽트 (위임)
  li   t0, PLIC_H0_MIE1          # M 컨텍스트는 끄고
  sw   zero, 0(t0)
  li   t0, MIE_MEIE
  csrc mie, t0
  li   t0, MIE_SEIE              # mideleg.SEI : S 외부 인터럽트를 S 가 직접 처리 (stvec 으로)
  csrw mideleg, t0
  csrs mie, t0                   # mie.SEIE (= sie.SEIE)
  li   t0, PLIC_H0_SIE1          # PLIC: ID 35 를 S 컨텍스트에서 enable
  li   t1, TB_IRQ0_BIT
  sw   t1, 0(t0)
  li   s5, 0
  li   s7, 0
  M_TO_S s_part2

  .balign 64
s_part2:                         # ---- S 모드
  csrsi sstatus, SSTATUS_SIE     # sstatus.SIE : S 모드 전역 enable
  li   a5, 0
  li   t0, TBDEV_BASE
  li   t1, 40
  MARK(2)
  sd   t1, TBDEV_IRQ0_SET(t0)
  BUSY s_busy2
  MARK(0)
  csrci sstatus, SSTATUS_SIE
  S_TO_M m_part2

m_part2:                         # ---- M 모드
  mv   s0, a5
  REPORT "s2_irq_count", s5
  REPORT "s2_cause_history", s7
  REPORT "s2_scause", s8
  la   t1, s_busy2
  sub  t1, s9, t1
  srli t1, t1, 2
  REPORT "s2_sepc_index_in_busy", t1
  srli t1, s10, 8
  andi t1, t1, 1
  REPORT "s2_sstatus_SPP_at_entry(1=S)", t1
  srli t1, s10, 5
  andi t1, t1, 1
  REPORT "s2_sstatus_SPIE_at_entry", t1
  srli t1, s10, 1
  andi t1, t1, 1
  REPORT "s2_sstatus_SIE_at_entry", t1
  REPORT "s2_claim_id", s6
  REPORT "s2_busy_count", s0
  EXPECT s5, 1
  EXPECT s6, TB_IRQ0_ID
  EXPECT s0, BUSY_N

  # ------------------------------------------------ MARK 3 : S 실행 중 M 외부 인터럽트, mstatus.MIE = 0
  li   t0, PLIC_H0_SIE1
  sw   zero, 0(t0)
  li   t0, MIE_SEIE
  csrc mie, t0
  csrw mideleg, zero
  li   t0, PLIC_H0_MIE1
  li   t1, TB_IRQ0_BIT
  sw   t1, 0(t0)
  li   t0, MIE_MEIE
  csrs mie, t0
  csrci mstatus, MSTATUS_MIE     # MIE = 0
  li   t0, MSTATUS_MPIE          # MPIE = 0 -> mret 뒤에도 MIE = 0
  csrc mstatus, t0
  li   s5, 0
  li   s7, 0
  M_TO_S s_part3

  .balign 64
s_part3:                         # ---- S 모드 (mstatus.MIE = 0, sstatus.SIE = 0)
  li   a5, 0
  li   t0, TBDEV_BASE
  li   t1, 40
  MARK(3)
  sd   t1, TBDEV_IRQ0_SET(t0)
  BUSY s_busy3
  MARK(0)
  S_TO_M m_part3

m_part3:                         # ---- M 모드
  mv   s0, a5
  REPORT "m3_irq_count", s5
  REPORT "m3_mcause", s8
  la   t1, s_busy3
  sub  t1, s9, t1
  srli t1, t1, 2
  REPORT "m3_mepc_index_in_busy", t1
  srli t1, s10, 11
  andi t1, t1, 3
  REPORT "m3_mstatus_MPP_at_entry(1=S)", t1
  srli t1, s10, 7
  andi t1, t1, 1
  REPORT "m3_mstatus_MPIE_at_entry", t1
  REPORT "m3_busy_count", s0
  EXPECT s5, 1
  EXPECT s0, BUSY_N

  # ------------------------------------------------ MARK 4 : M 실행 중 위임된 SEI -> S 로 내려갈 때까지 보류
  li   t0, PLIC_H0_MIE1
  sw   zero, 0(t0)
  li   t0, MIE_MEIE
  csrc mie, t0
  li   t0, MIE_SEIE
  csrw mideleg, t0
  csrs mie, t0
  li   t0, PLIC_H0_SIE1
  li   t1, TB_IRQ0_BIT
  sw   t1, 0(t0)
  csrsi mstatus, MSTATUS_MIE     # M 의 전역 enable 을 켜도 위임된 인터럽트는 M 에서 받지 않는다
  csrsi sstatus, SSTATUS_SIE     # S 로 내려가면 바로 받도록 미리 켜 둔다
  li   s5, 0
  li   s7, 0
  li   a5, 0
  li   t0, TBDEV_BASE
  li   t1, 10
  MARK(4)
  sd   t1, TBDEV_IRQ0_SET(t0)
  BUSY m_busy4                   # 이 사이 PLIC S 요청 -> mip.SEIP = 1 이지만 trap 없음
  csrr s1, mip
  mv   s2, s5                    # 지금까지 횟수 (0 이어야 함)
  M_TO_S s_part4

  .balign 64
s_part4:                         # ---- S 모드 : 이 명령이 실행되기 전에 (mret 에서) 이미 SEI 로 들어간다. sepc = 여기
  addi a5, a5, 1
  addi a5, a5, 1
  addi a5, a5, 1
  addi a5, a5, 1
  MARK(0)
  csrci sstatus, SSTATUS_SIE
  S_TO_M m_part4

m_part4:                         # ---- M 모드
  mv   s0, a5
  srli s1, s1, 9
  andi s1, s1, 1
  REPORT "m4_mip_SEIP_while_in_M", s1
  REPORT "m4_irq_count_while_in_M", s2
  REPORT "m4_irq_count_after_mret_to_S", s5
  REPORT "m4_scause", s8
  la   t1, s_part4
  sub  t1, s9, t1
  REPORT "m4_sepc_minus_s_part4", t1
  REPORT "m4_busy_count", s0
  EXPECT s2, 0
  EXPECT s5, 1
  EXPECT s0, BUSY_N+4

  csrci mstatus, MSTATUS_MIE
  csrw mie, zero
  csrw mideleg, zero
  j    pass

# ============================================================================ M 벡터 테이블
#  mtvec = m_vectors | 1. 동기 예외 -> +0x00, 인터럽트 cause n -> +4*n.
  .balign 64
m_vectors:
  j    m_sync                    #  0 : 예외 (ecall 등)
  j    m_unexpected              #  1 : SSI
  j    m_unexpected              #  2
  j    m_unexpected              #  3 : MSI
  j    m_unexpected              #  4
  j    m_unexpected              #  5 : STI
  j    m_unexpected              #  6
  j    m_unexpected              #  7 : MTI
  j    m_unexpected              #  8
  j    m_unexpected              #  9 : SEI (위임하지 않았을 때)
  j    m_unexpected              # 10
  j    m_mei                     # 11 : MEI

# ---------------------------------------------------------------- M 외부 인터럽트 핸들러
m_mei:
  addi sp, sp, -16               # (1) 문맥 저장 : 핸들러가 쓰는 레지스터만
  sd   t0, 0(sp)
  sd   t1, 8(sp)
  csrr s11, mcycle               #     (학습용 기록)
  csrr s8, mcause
  csrr s9, mepc
  csrr s10, mstatus
  addi s5, s5, 1
  slli s7, s7, 8
  ori  s7, s7, 11
  li   t0, PLIC_H0_MCLAIM        # (2) claim : 가장 높은 우선순위 ID 를 받는다. PLIC 은 그 소스의 pending 을 지운다
  lw   s6, 0(t0)
  beqz s6, 1f                    #     0 = 받을 것이 없음 (다른 컨텍스트가 먼저 가져감)
  li   t1, TBDEV_BASE            # (3) 장치 처리 : 장치 쪽 원인을 없앤다 (level 선을 내린다)
  sd   zero, TBDEV_IRQ0_CLR(t1)
  sw   s6, 0(t0)                 # (4) complete : 같은 ID 를 써서 이 소스를 다시 받을 수 있게 한다
1:
  ld   t1, 8(sp)                 # (5) 문맥 복구
  ld   t0, 0(sp)
  addi sp, sp, 16
  mret                           # (6) MIE <- MPIE, 모드 <- MPP, PC <- mepc

# ---------------------------------------------------------------- M 동기 예외 : S 의 ecall 서비스
#  a7 = 0 : M 모드의 a0 주소로 돌아간다 (S_TO_M)
m_sync:
  csrr t0, mcause
  li   t1, 9                     # Environment call from S-mode
  bne  t0, t1, __default_trap
  bnez a7, __default_trap
  csrw mepc, a0
  li   t0, MSTATUS_MPP           # MPP = M
  csrs mstatus, t0
  mret

m_unexpected:
  j    __default_trap

# ============================================================================ S 벡터 테이블
#  stvec = s_vectors | 1. 위임된 trap 만 여기로 온다
  .balign 64
s_vectors:
  j    s_unexpected              #  0 : 예외
  j    s_unexpected              #  1 : SSI
  j    s_unexpected              #  2
  j    s_unexpected              #  3
  j    s_unexpected              #  4
  j    s_unexpected              #  5 : STI
  j    s_unexpected              #  6
  j    s_unexpected              #  7
  j    s_unexpected              #  8
  j    s_sei                     #  9 : SEI

# ---------------------------------------------------------------- S 외부 인터럽트 핸들러
s_sei:
  addi sp, sp, -16               # (1) 문맥 저장
  sd   t0, 0(sp)
  sd   t1, 8(sp)
  rdcycle s11                    #     (mcounteren.CY = 1 이라 S 에서 읽힌다)
  csrr s8, scause
  csrr s9, sepc
  csrr s10, sstatus
  addi s5, s5, 1
  slli s7, s7, 8
  ori  s7, s7, 9
  li   t0, PLIC_H0_SCLAIM        # (2) claim : S 컨텍스트의 claim 레지스터
  lw   s6, 0(t0)
  beqz s6, 1f
  li   t1, TBDEV_BASE            # (3) 장치 처리
  sd   zero, TBDEV_IRQ0_CLR(t1)
  sw   s6, 0(t0)                 # (4) complete
1:
  ld   t1, 8(sp)                 # (5) 문맥 복구
  ld   t0, 0(sp)
  addi sp, sp, 16
  sret                           # (6) SIE <- SPIE, 모드 <- SPP, PC <- sepc

s_unexpected:                    # S 에서는 출력할 수 없으므로 M 으로 넘긴다 (ecall a7=1 -> m_sync 에서 실패 처리)
  li   a7, 1
  ecall
