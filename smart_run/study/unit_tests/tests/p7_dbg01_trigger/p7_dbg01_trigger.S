# ============================================================================
# p7_dbg01_trigger : 하드웨어 trigger(mcontrol) - 실행 breakpoint, store/load watchpoint
#
#  tselect(0x7A0) 로 trigger 를 고르고, tdata1(0x7A1) 에 조건, tdata2(0x7A2) 에 비교 주소를 쓴다.
#  tdata1 (mcontrol, type = 2) : type[63:60] dmode[59] hit[20] select[19] timing[18] action[15:12]
#                                chain[11] match[10:7] m[6] s[4] u[3] execute[2] store[1] load[0]
#  action = 0 이면 breakpoint 예외(mcause 3), 1 이면 debug mode 진입 (aq_dtu_mcontrol.v:515-517)
#  M 모드에서 action = 0 trigger 는 tcontrol(0x7A5).MTE = 1 일 때만 동작한다 (aq_dtu_mcontrol.v:711)
#
#  MARK 1 : 실행 breakpoint  - bp_target 의 명령을 실행하기 전에 trap. mepc = mtval = 그 주소
#  MARK 2 : store watchpoint - 같은 주소의 load 는 통과, store 에서 trap
#  MARK 3 : load watchpoint  - 다른 주소 load 는 통과, 같은 주소 load 에서 trap
#  MARK 4 : tcontrol.MTE = 0 이면 같은 breakpoint 가 무시된다
#  trap_handler : 원인 기록 후 tdata1 = 0 (trigger 끔) 으로 만들고 mret -> 그 명령을 다시 실행
#                 s6 = trap 안에서 읽은 tcontrol, s8 = mcause, s9 = mepc, s10 = mtval, s11 = trap 횟수
# GTKW: dbg rt
# ZOOM: mark
# ============================================================================
#include "study.h"

#define CSR_TSELECT   0x7a0
#define CSR_TDATA1    0x7a1
#define CSR_TDATA2    0x7a2
#define CSR_TINFO     0x7a4
#define CSR_TCONTROL  0x7a5
#define TCONTROL_MTE  (1 << 3)
#define MC_TYPE2      (2 << 60)
#define MC_M          (1 << 6)
#define MC_EXEC       (MC_TYPE2 | MC_M | (1 << 2))
#define MC_STORE      (MC_TYPE2 | MC_M | (1 << 1))
#define MC_LOAD       (MC_TYPE2 | MC_M | (1 << 0))

  .text
  .globl main
main:
  li   s11, 0

  # ---------------------------------------------------------------- trigger 개수와 종류
  li   s1, 0
  li   t1, 0
1:
  csrw CSR_TSELECT, t1
  csrr t2, CSR_TSELECT
  bne  t2, t1, 2f                 # 없는 번호를 쓰면 다른 값이 읽힌다
  addi s1, s1, 1
  addi t1, t1, 1
  li   t3, 16
  blt  t1, t3, 1b
2:
  REPORT "trigger_count", s1
  csrw CSR_TSELECT, zero
  csrr s2, CSR_TINFO
  REPORT "tinfo_trigger0", s2     # 지원하는 type 의 비트맵 (bit 2 = mcontrol)
  li   t0, TCONTROL_MTE
  csrs CSR_TCONTROL, t0

  # ---------------------------------------------------------------- MARK 1 : 실행 breakpoint
  la   t1, bp_target
  csrw CSR_TDATA2, t1
  li   t0, MC_EXEC
  csrw CSR_TDATA1, t0
  li   s3, 0
  MARK(1)
bp_target:
  addi s3, s3, 1
  MARK(0)
  EXPECT s11, 1
  EXPECT s8, 3
  EXPECT s3, 1                    # trap 뒤 다시 실행되어 한 번만 더해진다
  la   t1, bp_target
  sub  t2, s9, t1
  EXPECT t2, 0                    # mepc = breakpoint 주소
  sub  t2, s10, t1
  EXPECT t2, 0                    # mtval = breakpoint 주소
  REPORT "m1_mcause", s8
  REPORT "m1_tcontrol_in_handler", s6

  # ---------------------------------------------------------------- MARK 2 : store watchpoint
  la   s4, watch_var
  csrw CSR_TDATA2, s4
  li   t0, MC_STORE
  csrw CSR_TDATA1, t0
  li   t2, 0x55
  MARK(2)
  lw   t3, 0(s4)                  # load : 통과
m2_store:
  sw   t2, 0(s4)                  # store : trap, 돌아와서 다시 실행
  MARK(0)
  EXPECT s11, 2
  sub  t1, s10, s4
  EXPECT t1, 0                    # mtval = 데이터 주소
  lw   t3, 0(s4)
  EXPECT t3, 0x55                 # store 는 결국 한 번 실행되었다
  la   t1, m2_store
  sub  t2, s9, t1
  EXPECT t2, 0                    # mepc = store 명령 (timing = 0 : 실행 전에 trap)
  REPORT "m2_mcause", s8

  # ---------------------------------------------------------------- MARK 3 : load watchpoint
  csrw CSR_TDATA2, s4
  li   t0, MC_LOAD
  csrw CSR_TDATA1, t0
  MARK(3)
  lw   t3, 4(s4)                  # 다른 주소 : 통과
  lw   t3, 0(s4)                  # 같은 주소 : trap
  MARK(0)
  EXPECT s11, 3
  sub  t1, s10, s4
  EXPECT t1, 0

  # ---------------------------------------------------------------- MARK 4 : MTE = 0
  li   t0, TCONTROL_MTE
  csrc CSR_TCONTROL, t0
  la   t1, bp2
  csrw CSR_TDATA2, t1
  li   t0, MC_EXEC
  csrw CSR_TDATA1, t0
  MARK(4)
bp2:
  addi s3, s3, 1
  MARK(0)
  EXPECT s11, 3                   # trap 이 일어나지 않았다
  csrw CSR_TDATA1, zero
  REPORT "trap_count", s11
  j    pass

# ----------------------------------------------------------------------------
  .balign 64
  .globl trap_handler
trap_handler:
  csrr s6, CSR_TCONTROL
  csrr s8, mcause
  csrr s9, mepc
  csrr s10, mtval
  addi s11, s11, 1
  csrw CSR_TDATA1, zero           # trigger 를 끄고 같은 명령으로 돌아간다
  mret

  .data
  .balign 64
watch_var: .word 0, 0x77
