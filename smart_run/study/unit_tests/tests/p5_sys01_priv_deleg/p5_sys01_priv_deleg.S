# ============================================================================
# p5_sys01_priv_deleg : 특권 모드 전환 M -> S -> U 와 trap 위임(medeleg)
#
#  흐름 (waveform 의 cp0_priv: 11=M 01=S 00=U)
#   M  : stvec 설정, medeleg[8]=1 (U 의 ecall 을 S 로 위임), MPP=S, mret        -> MARK 1
#   (시작 전 M 에서 sstatus.SIE 를 써서 mstatus.SIE 가 바뀌는지 확인 : sstatus = mstatus 의 '창')
#   S  : SPP=U, sepc=u_entry, sret                                                -> MARK 2
#   U  : ecall (cause 8)  -> 위임되었으므로 S 의 stvec 으로                      -> MARK 3
#   S  : scause/sepc/sstatus.SPP 기록, S 에서 ecall (cause 9, 위임 안 됨) -> M    -> MARK 4
#   M  : mcause=9, mstatus.MPP=S 기록 후 mret -> S
#   S  : sepc+4, sret -> U                                                        -> MARK 5
#   U  : csrr mstatus (U 에서 M CSR 접근 -> illegal, cause 2, 위임 안 됨) -> M     -> MARK 6
#   M  : MPP=U 확인, 테스트 종료 처리
#
#  레지스터: s1 = sstatus 실험, S handler = s2..s4, M handler = s5..s11, t3/t4
# GTKW: rt cp0
# ============================================================================
#include "study.h"

  .text
  .option norvc
  .globl main
main:
  # sstatus 는 mstatus 의 일부 비트만 보여 주는 '창'이다 : sstatus.SIE 를 쓰면 mstatus.SIE 가 바뀐다
  csrsi sstatus, 2
  csrr s1, mstatus
  csrci sstatus, 2
  andi s1, s1, 2
  srli s1, s1, 1

  la   t0, s_trap
  csrw stvec, t0
  li   t0, (1 << 8)              # medeleg[8] : Environment call from U-mode -> S
  csrw medeleg, t0
  csrw mideleg, zero

  li   t0, (3 << 11)             # MPP = S(01)
  csrc mstatus, t0
  li   t0, (1 << 11)
  csrs mstatus, t0
  la   t0, s_entry
  csrw mepc, t0
  MARK(1)
  mret

# ============================================================================ S-mode
  .balign 64
s_entry:
  MARK(2)
  li   t0, (1 << 8)              # sstatus.SPP = 0 -> sret 하면 U 로
  csrc sstatus, t0
  la   t0, u_entry
  csrw sepc, t0
  sret

# ============================================================================ U-mode
  .balign 64
u_entry:
  MARK(3)
  ecall                          # -> S (위임)
u_after_ecall:
  MARK(6)
  csrr t1, mstatus               # -> illegal (M) : U 는 M CSR 에 접근할 수 없다
  j    fail                      # (여기 오면 안 됨)

# ============================================================================ S handler
  .balign 64
s_trap:
  csrr s2, scause
  csrr s3, sepc
  csrr s4, sstatus
  MARK(4)
  ecall                          # S -> M (cause 9, 위임 안 됨)
  MARK(5)
  addi t0, s3, 4
  csrw sepc, t0
  sret                           # -> U (SPP=0)

# ============================================================================ M handler
  .balign 64
  .globl trap_handler
trap_handler:
  csrr t3, mcause
  li   t4, 9
  beq  t3, t4, m_from_s
  li   t4, 2
  beq  t3, t4, m_from_u_illegal
  j    __default_trap

m_from_s:                        # S 의 ecall
  mv   s5, t3
  csrr s6, mstatus
  csrr s7, mepc
  addi t4, s7, 4
  csrw mepc, t4
  mret                           # MPP=S 이므로 S 로 돌아감

m_from_u_illegal:                # U 의 불법 CSR 접근
  mv   s8, t3
  csrr s9, mstatus
  csrr s10, mtval
  csrr s11, mepc
  li   t4, (3 << 11)             # MPP = M
  csrs mstatus, t4
  la   t4, m_done
  csrw mepc, t4
  mret

# ============================================================================ M-mode
m_done:
  MARK(0)
  REPORT "s_scause_from_u_ecall", s2
  la   t1, u_entry
  sub  s3, s3, t1
  REPORT "s_sepc_minus_u_entry", s3
  srli s4, s4, 8
  andi s4, s4, 1
  REPORT "s_sstatus_SPP(0=U)", s4
  REPORT "m_mcause_from_s_ecall", s5
  srli t1, s6, 11
  andi t1, t1, 3
  REPORT "m_mstatus_MPP_from_s(1=S)", t1
  REPORT "mstatus_SIE_after_writing_sstatus_SIE", s1
  REPORT "m_mcause_from_u_illegal", s8
  srli t1, s9, 11
  andi t1, t1, 3
  REPORT "m_mstatus_MPP_from_u(0=U)", t1
  REPORT "m_mtval_from_u_illegal(inst)", s10
  csrw medeleg, zero
  csrci mstatus, 2
  j    pass
