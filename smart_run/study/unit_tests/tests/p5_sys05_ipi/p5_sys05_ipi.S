# ============================================================================
# p5_sys05_ipi : 소프트웨어 인터럽트(IPI) - CLINT MSIP, SBI 방식 S 전달, C906 SSIP0, 우선순위
#
#  IPI(Inter-Processor Interrupt) = 다른 hart 의 CLINT MSIP 에 1 을 써서 그 hart 에 MSI(cause 3)를 거는 것.
#    hart i -> hart j :  메시지를 공유 메모리에 쓰고, fence, MSIP[j] (CLINT_BASE + 4*j) = 1  (doorbell)
#    받는 hart        :  MSI 핸들러가 메시지를 읽고, 자기 MSIP 를 0 으로 해제
#  C906 은 단일 hart 라 CLINT 에 MSIP0 만 있다 (clint_func.v : MSIP1~3 은 주소 상수만 있고 acc_err).
#  그래서 hart 0 가 자기 자신에게 보낸다 (self-IPI). 받는 쪽 동작은 멀티코어와 같다.
#
#  MARK 1 : M -> M : 메일박스 + MSIP0 = 1 -> MSI (mcause 3, mtvec+0x0C) -> 메시지 읽고 MSIP0 = 0
#  MARK 2 : S 가 IPI 요청 (SBI 방식, Linux + OpenSBI 와 같은 흐름)
#           S: ecall(a7=SBI_SEND_IPI) -> M: 메일박스 + MSIP0 = 1, mret -> S 로 돌아오자마자 MSI -> M
#           -> M 의 MSI 핸들러가 mip.SSIP = 1 로 전달 -> mret -> S 의 SSI (scause 1, stvec+0x04)
#  MARK 3 : S -> S : C906 확장. S 가 CLINT SSIP0 에 직접 1 (MXSTATUS.CLINTEE = 1) -> SSI. M 개입 없음
#  MARK 4 : 우선순위 : MIE = 0 인 동안 MSI 와 MEI(TB 장치)를 둘 다 pending -> MIE = 1 -> MEI 먼저, 그다음 MSI
#
#  레지스터 : main = s0..s4, a5 / 핸들러가 기록 = s5 횟수, s6 받은 메시지 또는 claim ID,
#             s7 cause 이력 (s7 = s7<<8 | cause), s8 cause, s9 epc, s10 status, s11 진입 cycle
# GTKW: irq trap
# ============================================================================
#include "study.h"

#define MSTATUS_MIE   (1 << 3)
#define MSTATUS_MPP   (3 << 11)
#define SSTATUS_SIE   (1 << 1)
#define MIP_SSIP      (1 << 1)
#define MIP_MSIP      (1 << 3)
#define MIE_SSIE      (1 << 1)
#define MIE_MSIE      (1 << 3)
#define MIE_MEIE      (1 << 11)
#define TB_IRQ0_BIT   (1 << (TB_IRQ0_ID - 32))

#define SBI_SEND_IPI  1                  /* ecall a7 : S 가 M 에 IPI 를 부탁 (OpenSBI 의 sbi_send_ipi 흉내) */
#define MSG_M         0x1234             /* 메일박스 메시지 : M 이 처리                            */
#define MSG_FWD_S     0x5555             /* 메일박스 메시지 : S 소프트웨어 인터럽트로 넘겨 달라     */

.macro M_TO_S label
  li   t0, MSTATUS_MPP
  csrc mstatus, t0
  li   t0, (1 << 11)
  csrs mstatus, t0
  la   t0, \label
  csrw mepc, t0
  mret
.endm

.macro S_TO_M label
  la   a0, \label
  li   a7, 0
  ecall
.endm

.macro BUSY label, n
\label:
  .rept \n
  addi a5, a5, 1
  .endr
.endm

  .data
  .balign 8
ipi_mailbox: .dword 0

  .text
  .option norvc
  .globl main
main:
  la   t0, m_vectors
  ori  t0, t0, 1                 # vectored
  csrw mtvec, t0
  la   t0, s_vectors
  ori  t0, t0, 1
  csrw stvec, t0
  li   t0, 7
  csrw mcounteren, t0
  csrw medeleg, zero
  csrw mideleg, zero

  # ------------------------------------------------ MARK 1 : M -> M self-IPI
  li   t0, MIE_MSIE              # mie.MSIE
  csrw mie, t0
  csrsi mstatus, MSTATUS_MIE
  li   s5, 0
  li   s6, 0
  li   s7, 0
  li   a5, 0
  la   t0, ipi_mailbox
  li   t1, MSG_M
  li   t2, CLINT_MSIP0           # 멀티코어라면 CLINT_MSIP0 + 4 * 받는 hart 번호
  li   t3, 1
  MARK(1)
  sd   t1, 0(t0)                 # (1) 메시지를 공유 메모리에
  fence w, o                     # (2) 메시지(메모리 쓰기)가 doorbell(장치 쓰기)보다 먼저 보이도록
  sw   t3, 0(t2)                 # (3) doorbell : MSIP0 = 1
  BUSY m_busy1, 60
  MARK(0)
  mv   s0, a5
  REPORT "m1_irq_count", s5
  REPORT "m1_mcause", s8
  REPORT "m1_message_received", s6
  la   t1, m_busy1
  sub  t1, s9, t1
  srli t1, t1, 2
  REPORT "m1_mepc_index_in_busy", t1
  REPORT "m1_busy_count", s0
  EXPECT s5, 1
  EXPECT s6, MSG_M
  EXPECT s0, 60

  # ------------------------------------------------ MARK 2 : S 의 IPI 요청 -> M 이 보내고 -> M 이 S 로 전달
  li   t0, MIE_SSIE              # mideleg.SSI : S 소프트웨어 인터럽트는 S 가 처리
  csrw mideleg, t0
  li   t0, MIE_MSIE | MIE_SSIE   # mie.MSIE (M 이 IPI 를 받음), mie.SSIE (S 가 전달받음)
  csrw mie, t0
  li   s5, 0
  li   s6, 0
  li   s7, 0
  M_TO_S s_part2

  .balign 64
s_part2:                         # ---- S 모드
  csrsi sstatus, SSTATUS_SIE
  li   a5, 0
  MARK(2)
  li   a0, 1                     # hart mask : hart 0
  li   a7, SBI_SEND_IPI
  ecall                          # -> M (m_sync) : 메일박스 + MSIP0 = 1 -> mret
  BUSY s_busy2, 60               # 여기서 MSI(M) -> SSI(S) 가 차례로 끼어든다
  MARK(0)
  csrci sstatus, SSTATUS_SIE
  S_TO_M m_part2

m_part2:
  mv   s0, a5
  REPORT "s2_irq_count", s5
  REPORT "s2_cause_history(3=MSI,1=SSI)", s7
  REPORT "s2_last_scause", s8
  la   t1, s_busy2
  sub  t1, s9, t1
  srli t1, t1, 2
  REPORT "s2_sepc_index_in_busy", t1
  REPORT "s2_message_received_by_M", s6
  REPORT "s2_busy_count", s0
  EXPECT s5, 2
  EXPECT s7, 0x301
  EXPECT s0, 60

  # ------------------------------------------------ MARK 3 : S -> S, CLINT SSIP0 직접 (C906 CLINTEE)
  csrr t1, CSR_MXSTATUS
  srli s1, t1, 17
  andi s1, s1, 1                 # CLINTEE (reset 값 1)
  li   t0, MIE_SSIE
  csrw mie, t0
  li   s5, 0
  li   s7, 0
  M_TO_S s_part3

  .balign 64
s_part3:                         # ---- S 모드
  csrsi sstatus, SSTATUS_SIE
  li   a5, 0
  li   t0, CLINT_SSIP0
  li   t1, 1
  MARK(3)
  sw   t1, 0(t0)                 # S 모드에서 CLINT SSIP0 = 1 (S 레지스터라 S 접근 허용)
  BUSY s_busy3, 60
  MARK(0)
  csrci sstatus, SSTATUS_SIE
  S_TO_M m_part3

m_part3:
  mv   s0, a5
  REPORT "s3_mxstatus_CLINTEE", s1
  REPORT "s3_irq_count", s5
  REPORT "s3_scause", s8
  la   t1, s_busy3
  sub  t1, s9, t1
  srli t1, t1, 2
  REPORT "s3_sepc_index_in_busy", t1
  REPORT "s3_busy_count", s0
  EXPECT s5, 1
  EXPECT s0, 60

  # ------------------------------------------------ MARK 4 : MSI 와 MEI 가 동시에 pending
  csrw mideleg, zero
  li   t0, PLIC_PRIO(TB_IRQ0_ID)
  li   t1, 1
  sw   t1, 0(t0)
  li   t0, PLIC_H0_MTH
  sw   zero, 0(t0)
  li   t0, PLIC_H0_MIE1
  li   t1, TB_IRQ0_BIT
  sw   t1, 0(t0)
  li   t0, MIE_MSIE | MIE_MEIE
  csrw mie, t0
  csrci mstatus, MSTATUS_MIE     # MIE = 0 : 둘 다 pending 만
  li   s5, 0
  li   s7, 0
  la   t0, ipi_mailbox
  li   t1, MSG_M
  sd   t1, 0(t0)
  MARK(4)
  li   t0, TBDEV_BASE
  sd   zero, TBDEV_IRQ0_SET(t0)  # 외부 인터럽트 선 바로 1
  li   t0, CLINT_MSIP0
  li   t1, 1
  sw   t1, 0(t0)                 # IPI
  li   t2, (1 << 11) | MIP_MSIP
1:
  csrr t1, mip                   # mip.MEIP 와 mip.MSIP 가 둘 다 1 이 될 때까지
  and  t1, t1, t2
  bne  t1, t2, 1b
  mv   s1, s5                    # 지금까지 0
  csrsi mstatus, MSTATUS_MIE     # 여기서 MEI -> (mret 후) MSI 순서로 들어온다
  nop
  nop
  nop
  nop
  MARK(0)
  REPORT "m4_irq_count_while_MIE0", s1
  REPORT "m4_irq_count", s5
  REPORT "m4_cause_history(0xb03=MEI,MSI)", s7
  EXPECT s1, 0
  EXPECT s7, 0xb03

  csrci mstatus, MSTATUS_MIE
  csrw mie, zero
  j    pass

# ============================================================================ M 벡터 테이블
  .balign 64
m_vectors:
  j    m_sync                    #  0 : 예외
  j    m_unexpected              #  1 : SSI
  j    m_unexpected              #  2
  j    m_msi                     #  3 : MSI (IPI)
  j    m_unexpected              #  4
  j    m_unexpected              #  5
  j    m_unexpected              #  6
  j    m_unexpected              #  7 : MTI
  j    m_unexpected              #  8
  j    m_unexpected              #  9
  j    m_unexpected              # 10
  j    m_mei                     # 11 : MEI

# ---------------------------------------------------------------- M 소프트웨어 인터럽트 (IPI 수신)
m_msi:
  addi sp, sp, -16
  sd   t0, 0(sp)
  sd   t1, 8(sp)
  csrr s11, mcycle
  csrr s8, mcause
  csrr s9, mepc
  csrr s10, mstatus
  addi s5, s5, 1
  slli s7, s7, 8
  ori  s7, s7, 3
  la   t0, ipi_mailbox           # (1) 메시지 읽기
  ld   s6, 0(t0)
  sd   zero, 0(t0)
  li   t0, CLINT_MSIP0           # (2) 해제 : 자기 MSIP 를 0 으로 (멀티코어라면 MSIP[mhartid])
  sw   zero, 0(t0)
2:
  csrr t1, mip                   #     CLINT 쓰기가 mip 에 반영될 때까지 기다린 뒤 복귀 (p5_sys02 참고)
  andi t1, t1, MIP_MSIP
  bnez t1, 2b
  li   t0, MSG_FWD_S             # (3) S 로 넘겨 달라는 메시지면 mip.SSIP = 1 (S 소프트웨어 인터럽트)
  bne  s6, t0, 3f
  csrsi mip, MIP_SSIP
3:
  ld   t1, 8(sp)
  ld   t0, 0(sp)
  addi sp, sp, 16
  mret

# ---------------------------------------------------------------- M 외부 인터럽트 (MARK 4)
m_mei:
  addi sp, sp, -16
  sd   t0, 0(sp)
  sd   t1, 8(sp)
  csrr s8, mcause
  csrr s9, mepc
  addi s5, s5, 1
  slli s7, s7, 8
  ori  s7, s7, 11
  li   t0, PLIC_H0_MCLAIM
  lw   t1, 0(t0)                 # claim
  beqz t1, 1f
  li   t0, TBDEV_BASE            # 장치 해제가 먼저. complete 를 먼저 하면 그때 선이 아직 1 이라
  sd   zero, TBDEV_IRQ0_CLR(t0)  # PLIC gateway 가 다시 pending 시킨다 -> MEI 에 한 번 더 들어온다
  li   t0, PLIC_H0_MCLAIM
  sw   t1, 0(t0)                 # complete
1:
  ld   t1, 8(sp)
  ld   t0, 0(sp)
  addi sp, sp, 16
  mret

# ---------------------------------------------------------------- M 동기 예외 : S 의 ecall 서비스
#  a7 = 0            : M 모드의 a0 로 돌아간다
#  a7 = SBI_SEND_IPI : a0 = hart mask. 메일박스에 MSG_FWD_S 를 쓰고 MSIP0 = 1 (OpenSBI 의 sbi_ipi_send 와 같은 일)
m_sync:
  csrr t0, mcause
  li   t1, 9
  bne  t0, t1, __default_trap
  beqz a7, 1f
  li   t1, SBI_SEND_IPI
  bne  a7, t1, __default_trap
  la   t0, ipi_mailbox
  li   t1, MSG_FWD_S
  sd   t1, 0(t0)
  fence w, o
  li   t0, CLINT_MSIP0
  li   t1, 1
  sw   t1, 0(t0)                 # 받는 hart 의 MSIP
  csrr t0, mepc
  addi t0, t0, 4                 # ecall 다음 명령으로 복귀
  csrw mepc, t0
  mret
1:
  csrw mepc, a0
  li   t0, MSTATUS_MPP
  csrs mstatus, t0
  mret

m_unexpected:
  j    __default_trap

# ============================================================================ S 벡터 테이블
  .balign 64
s_vectors:
  j    s_unexpected              #  0 : 예외
  j    s_ssi                     #  1 : SSI

# ---------------------------------------------------------------- S 소프트웨어 인터럽트
s_ssi:
  addi sp, sp, -16
  sd   t0, 0(sp)
  sd   t1, 8(sp)
  rdcycle s11
  csrr s8, scause
  csrr s9, sepc
  csrr s10, sstatus
  addi s5, s5, 1
  slli s7, s7, 8
  ori  s7, s7, 1
  csrci sip, MIP_SSIP            # (1) M 이 csrs mip 로 세운 SSIP 는 sip 로 지운다     (MARK 2)
  li   t0, CLINT_SSIP0           # (2) CLINT SSIP0 로 세운 것은 CLINT 에서 지운다     (MARK 3)
  sw   zero, 0(t0)
2:
  csrr t1, sip
  andi t1, t1, MIP_SSIP
  bnez t1, 2b
  ld   t1, 8(sp)
  ld   t0, 0(sp)
  addi sp, sp, 16
  sret

s_unexpected:
  li   a7, 99
  ecall
