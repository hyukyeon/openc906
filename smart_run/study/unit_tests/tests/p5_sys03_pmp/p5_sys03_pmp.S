# ============================================================================
# p5_sys03_pmp : PMP (Physical Memory Protection)
#
#  pmpcfgN 바이트 = {L, 0, 0, A[1:0], X, W, R},  A: 0=OFF 1=TOR 2=NA4 3=NAPOT
#  NAPOT : pmpaddr = (base >> 2) | (size/8 - 1)   (하위의 연속된 1 개수가 크기를 나타냄)
#  C906 : 8 entry, 최소 단위 4KB, NA4 미지원 (UM 2.2.6)
#  우선순위 : 번호가 작은 entry 가 먼저. M-mode 는 L=1 인 entry 에만 영향을 받는다.
#
#  entry 0 : prot_page(4KB) NAPOT, R 만 허용
#  entry 7 : 전체 주소 RWX (crt0 가 설정)
#  MARK 1 : M-mode 에서 prot_page 에 store -> 성공 (L=0)
#  MARK 2 : U-mode 에서 load -> 성공, store -> store access fault (cause 7)
#  MARK 3 : entry 0 에 L=1 (lock) 직후 M-mode store  -> (C906) uTLB 에 캐시된 이전 권한 때문에 통과
#  MARK 4 : sfence.vma 후 M-mode store               -> store access fault. pmpaddr0 쓰기는 무시됨
#           C906 은 M-mode 접근도 uTLB 를 거치며, refill 때 PMP 권한(pmp_mmu_flg)을 엔트리에 저장한다
#           (aq_mmu_ptw.v PTW_MACH_PMP) -> PMP 를 바꾸면 sfence.vma 가 필요
#  M handler : s8=mcause s9=mepc s10=mtval, 명령 건너뛰기. U 의 ecall 이면 M 으로 복귀
# GTKW: lsu rt cp0
# ============================================================================
#include "study.h"

  .text
  .option norvc
  .globl main
main:
  li   s8, 0
  la   s1, prot_page
  srli t0, s1, 2
  ori  t0, t0, 0x1ff             # 4KB NAPOT : 4096/8 - 1 = 0x1ff
  csrw pmpaddr0, t0
  li   t0, (0x1f << 56) | 0x19   # entry7 = NAPOT RWX(유지), entry0 = NAPOT(0x18) | R(0x1)
  csrw pmpcfg0, t0

  # ------------------------------------------------ MARK 1 : M-mode store (L=0)
  MARK(1)
  li   t1, 0x1234
  sd   t1, 0(s1)
  MARK(0)
  ld   t2, 0(s1)
  REPORT "m_store_unlocked_readback", t2
  REPORT "m_store_unlocked_mcause(0=none)", s8

  # ------------------------------------------------ MARK 2 : U-mode
  li   t0, (3 << 11)             # MPP = U(00)
  csrc mstatus, t0
  la   t0, u_code
  csrw mepc, t0
  li   s6, 0                     # U 에서 load 한 값
  mret

  .balign 64
u_code:
  MARK(2)
  ld   s6, 0(s1)                 # R 허용 -> 성공
  li   t1, 0x5678
  sd   t1, 8(s1)                 # W 불허 -> store access fault (7)
  mv   s5, s8                    # handler 가 남긴 mcause
  mv   s4, s10                   # mtval
  ecall                          # -> M (cause 8) : 테스트를 M 으로 되돌림

m_after_u:
  MARK(0)
  REPORT "u_load_value", s6
  REPORT "u_store_mcause", s5
  sub  s4, s4, s1
  REPORT "u_store_mtval_minus_page", s4

  # ------------------------------------------------ MARK 3 : lock
  li   s8, 0
  li   t0, 0x80                  # entry0 L=1
  csrs pmpcfg0, t0
  MARK(3)
  li   t1, 0x9999
  sd   t1, 16(s1)                # sfence.vma 전: uTLB 에 캐시된 이전 권한으로 접근 -> ?
  mv   s7, s8
  li   s8, 0
  sfence.vma                     # uTLB/jTLB 무효화 -> PMP 권한을 다시 읽어 온다
  MARK(4)
  sd   t1, 24(s1)                # 이제 M 도 W 불허 -> fault
  mv   s5, s8
  li   t0, -1
  csrw pmpaddr0, t0              # locked entry 는 쓰기가 무시된다
  csrr s3, pmpaddr0
  csrr s2, pmpcfg0
  MARK(0)
  REPORT "m_store_locked_before_sfence_mcause", s7
  REPORT "m_store_locked_after_sfence_mcause", s5
  srli t1, s1, 2
  ori  t1, t1, 0x1ff
  sub  s3, s3, t1
  REPORT "pmpaddr0_change_after_lock(0=ignored)", s3
  andi s2, s2, 0xff
  REPORT "pmpcfg0_entry0", s2
  j    pass                      # (lock 은 리셋 전까지 풀리지 않는다)

# ----------------------------------------------------------------------------
  .balign 64
  .globl trap_handler
trap_handler:
  csrr s8, mcause
  csrr s9, mepc
  csrr s10, mtval
  li   t3, 8                     # ecall from U
  beq  s8, t3, 1f
  addi t3, s9, 4
  csrw mepc, t3
  mret
1:
  li   t3, (3 << 11)
  csrs mstatus, t3               # MPP = M
  la   t3, m_after_u
  csrw mepc, t3
  mret

  .data
  .balign 4096
prot_page: .space 4096
