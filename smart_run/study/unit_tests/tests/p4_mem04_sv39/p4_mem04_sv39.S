# ============================================================================
# p4_mem04_sv39 : Sv39 가상 메모리 - 3 단계 page walk, TLB, page fault
#
#  페이지 테이블 (모두 .data 의 4KB 정렬 영역)
#    root[0] : VA 0x0000_0000 ~ 0x3FFF_FFFF  -> 1GB gigapage, identity (코드/데이터/스택)
#    root[1] : VA 0x4000_0000 ~             -> L1 테이블 (non-leaf)
#      l1[0] : -> L0 테이블 (non-leaf)
#        l0[0] : VA 0x4000_0000 -> PA target_page (4KB leaf, R W A D)
#        l0[1] : VA 0x4000_1000 -> 0 (invalid)  -> load page fault (13)
#        l0[2] : VA 0x4000_2000 -> PA target_page, R 만 (W=0) -> store page fault (15)
#  M-mode 는 satp 와 무관하게 물리 주소를 쓴다. S-mode 로 내려가서 접근한다.
#
#  MARK 1 : S-mode 진입 후 VA 0x4000_0000 첫 load   (uTLB/jTLB miss -> PTW 3 단계)
#  MARK 2 : 같은 페이지 두 번째 load                (TLB hit)
#  MARK 3 : VA 0x4000_1000 load -> load page fault  (M-mode handler 가 기록 후 건너뜀)
#  MARK 4 : VA 0x4000_2000 store -> store page fault
#  MARK 5 : VA[12] 가 PA[12] 와 다른 주소(다른 page color)/같은 주소로 쓰고 읽기 -> VIPT alias 처리 확인
#  보고: 사이클, mcause/mtval, 읽은 값
#  PTW 의 메모리 접근(root->l1->l0)은 waveform 의 lsu_dc_pa 에서 0x40008, 0x41000, 0x42000 으로 보인다.
#
#  [주의] MXSTATUS.MAEE=0 (sysmap 속성 사용) 로 실행했을 때 이 SoC/RTL 에서는 S-mode 의 fetch/load 가
#         매번 버스로 나가는(캐시되지 않는) 동작이 관찰되었다. 공식 MMU 테스트(tests/cases/MMU)처럼
#         MAEE=1 로 두고 PTE[63:59] 에 속성(0x0f: cacheable)을 넣는다.
#
#  trap_handler(M) : s8=mcause s9=mepc s10=mtval, mepc+4 로 복귀. mcause=9(S ecall) 이면 M 으로 돌아옴
# GTKW: ex lsu rt cp0 bus
# ============================================================================
#include "study.h"

#define PTE_V (1 << 0)
#define PTE_R (1 << 1)
#define PTE_W (1 << 2)
#define PTE_X (1 << 3)
#define PTE_U (1 << 4)
#define PTE_G (1 << 5)
#define PTE_A (1 << 6)
#define PTE_D (1 << 7)
#define VA_PAGE  0x40000000
/* C906 확장 PTE 속성 PTE[63:59] = {SO, C, B, SH, SEC} (MXSTATUS.MAEE=1 일 때 사용)
 * 0x0f = SO0 C1 B1 SH1 SEC1 : cacheable/bufferable 메모리 (공식 MMU 테스트와 동일) */
#ifndef THEAD_ATTR
#define THEAD_ATTR 0x0f
#endif

/* PTE = (PA >> 12) << 10 | flags | THEAD_ATTR << 59 */
.macro MKPTE reg, pa_reg, flags
  srli \reg, \pa_reg, 12
  slli \reg, \reg, 10
  ori  \reg, \reg, \flags
  li   t5, THEAD_ATTR
  slli t5, t5, 59
  or   \reg, \reg, t5
.endm

  .text
  .option norvc
  .globl main
main:
  # ---- 페이지 테이블 구성
  la   s1, root
  la   s2, l1
  la   s3, l0
  la   s4, target_page
  # root[0] : gigapage identity, PPN = 0
  li   t1, 0
  MKPTE t0, t1, (PTE_V | PTE_R | PTE_W | PTE_X | PTE_A | PTE_D)
  sd   t0, 0(s1)
  # root[1] -> l1 (non-leaf: R=W=X=0)
  MKPTE t0, s2, PTE_V
  sd   t0, 8(s1)
  # l1[0] -> l0
  MKPTE t0, s3, PTE_V
  sd   t0, 0(s2)
  # l0[0] -> target_page RW
  MKPTE t0, s4, (PTE_V | PTE_R | PTE_W | PTE_A | PTE_D)
  sd   t0, 0(s3)
  # l0[1] = 0 (invalid)
  sd   zero, 8(s3)
  # l0[2] -> target_page R only
  MKPTE t0, s4, (PTE_V | PTE_R | PTE_A)
  sd   t0, 16(s3)
  # l0[3] -> target_page RW (VA 0x4000_3000: VA[12]=1 = PA[12], 같은 page color)
  MKPTE t0, s4, (PTE_V | PTE_R | PTE_W | PTE_A | PTE_D)
  sd   t0, 24(s3)
  fence                          # 페이지 테이블을 메모리(D$)에 반영. PTW 는 D$ 를 통해 읽는다

  # ---- MXSTATUS.MAEE=1 : 페이지 속성(cacheable 등)을 PTE[63:59] 에서 가져온다
  li   t0, (1 << 21)
  csrs CSR_MXSTATUS, t0

  # ---- satp = MODE(8=Sv39) | ASID 0 | PPN(root)
  srli t0, s1, 12
  li   t1, 8
  slli t1, t1, 60
  or   t0, t0, t1
  csrw satp, t0
  sfence.vma

  # ---- S-mode 로 내려가기: mstatus.MPP = 01, mepc = s_code, mret
  li   t0, (3 << 11)
  csrc mstatus, t0
  li   t0, (1 << 11)
  csrs mstatus, t0
  la   t0, s_code
  csrw mepc, t0
  li   t0, 0x7                   # mcounteren: S-mode 가 cycle/time/instret 을 읽을 수 있게
  csrw mcounteren, t0
  mret

# ============================================================================ S-mode
  .balign 64
s_code:
  li   s7, VA_PAGE
  MARK(1)
  csrr s0, cycle                 # S 에서 mcycle 은 못 읽는다 -> cycle (mcounteren 기본 허용?)
  ld   a4, 0(s7)                 # TLB miss -> PTW
  addi a4, a4, 0
  csrr t0, cycle
  sub  s0, t0, s0
  MARK(2)
  csrr s1, cycle
  ld   a5, 8(s7)                 # TLB hit
  addi a5, a5, 0
  csrr t0, cycle
  sub  s1, t0, s1
  mv   s2, a4                    # 읽은 값
  li   t1, VA_PAGE + 0x3000
  ld   s11, 0(t1)                # 같은 물리 페이지를 VA[12]=1 인 주소로 읽기
  MARK(3)
  li   t1, VA_PAGE + 0x1000
  ld   a6, 0(t1)                 # load page fault -> M handler -> 다음 명령
  mv   s3, s8                    # handler 가 남긴 mcause
  mv   s4, s10                   # mtval
  MARK(4)
  li   t1, VA_PAGE + 0x2000
  sd   a6, 0(t1)                 # store page fault
  mv   s5, s8
  mv   s6, s10
  MARK(5)
  li   t1, 0x77778888
  sd   t1, 16(s7)                # VA 0x4000_0010 (VA[12]=0, PA[12]=1 : 다른 color) 로 쓰기
  li   t2, VA_PAGE + 0x3000
  ld   s9, 16(t2)                # 같은 물리 주소를 VA[12]=1 인 주소로 읽기
  li   t1, 0x9999aaaa
  sd   t1, 24(t2)                # VA 0x4000_3018 (같은 color) 로 쓰기
  ld   s10, 24(s7)               # 다른 color VA 로 읽기
  mv   a0, s9
  mv   a1, s10
  MARK(0)
  ecall                          # S -> M 복귀 요청 (mcause 9)

# ============================================================================ M-mode (복귀 후)
m_resume:
  mv   s9, a0                    # (S-mode 에서 a0/a1 에 남긴 값. REPORT 가 a0/a1 을 쓰므로 먼저 옮김)
  mv   s10, a1
  REPORT "s_first_load_cycles(ptw)", s0
  REPORT "s_second_load_cycles(tlb_hit)", s1
  REPORT "s_loaded_value", s2
  REPORT "s_loaded_value_same_color_va", s11
  REPORT "load_pf_mcause", s3
  REPORT "load_pf_mtval", s4
  REPORT "store_pf_mcause", s5
  REPORT "store_pf_mtval", s6
  REPORT "color1_read_after_color0_write", s9
  REPORT "color0_read_after_color1_write", s10
  la   t3, target_page
  ld   t3, 16(t3)                # M-mode, PA 로 읽기
  REPORT "pa_read_of_color0_write", t3
  la   t3, target_page
  ld   t3, 24(t3)
  REPORT "pa_read_of_color1_write", t3
  csrw satp, zero
  li   t0, (1 << 21)
  csrc CSR_MXSTATUS, t0
  j    pass

# ----------------------------------------------------------------------------
  .balign 64
  .globl trap_handler
trap_handler:
  csrr s8, mcause
  csrr s9, mepc
  csrr s10, mtval
  li   t4, 9                     # ecall from S
  beq  s8, t4, 1f
  addi t4, s9, 4
  csrw mepc, t4                  # fault 명령 건너뛰기 (MPP 는 S 로 유지됨)
  mret
1:
  li   t4, (3 << 11)             # MPP = M 으로 돌아감
  csrs mstatus, t4
  la   t4, m_resume
  csrw mepc, t4
  mret

  .data
  .balign 4096
root:        .space 4096
l1:          .space 4096
l0:          .space 4096
target_page: .dword 0x5A5A1234, 0x11112222, 0, 0   # 초기값은 data.pat 으로 메모리에 직접 적재
             .space 4096 - 32
