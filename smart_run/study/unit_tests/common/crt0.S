/* ==========================================================================
 * crt0.S - 학습용 최소 startup
 *   1) GPR 초기화 (x31 = mark = 0)
 *   2) mtvec = __trap_entry (direct mode) -> 테스트의 trap_handler 로 점프
 *   3) I$/D$/BHT/BTB 무효화 후 MHCR_DEFAULT 로 활성화 (prefetch 는 끔: 측정 재현성)
 *   4) HPM counter 3~9 에 이벤트 연결
 *   5) main 호출. main 은 ret 대신 "j pass" 또는 "j fail" 로 끝낸다.
 * ========================================================================== */
#include "study.h"

  .section .text.init, "ax"
  .globl _start
_start:
  .option push
  .option norvc
  li   x31, 0                    /* mark 를 가장 먼저 0 으로 */
  li   x1, 0
  li   x2, 0
  li   x3, 0
  li   x4, 0
  li   x5, 0
  li   x6, 0
  li   x7, 0
  li   x8, 0
  li   x9, 0
  li   x10, 0
  li   x11, 0
  li   x12, 0
  li   x13, 0
  li   x14, 0
  li   x15, 0
  li   x16, 0
  li   x17, 0
  li   x18, 0
  li   x19, 0
  li   x20, 0
  li   x21, 0
  li   x22, 0
  li   x23, 0
  li   x24, 0
  li   x25, 0
  li   x26, 0
  li   x27, 0
  li   x28, 0
  li   x29, 0
  li   x30, 0
  li   x31, 0
  .option pop

  la   sp, __stack_top
  la   t0, __trap_entry
  csrw mtvec, t0

  /* PMP entry 7 = 전체 주소 NAPOT RWX : PMP 엔트리가 하나라도 구현되어 있으면
   * 어떤 엔트리에도 매칭되지 않는 S/U 모드 접근은 실패하므로(Priv spec) S/U 테스트용으로 열어 둔다.
   * entry 0~6 은 테스트가 쓸 수 있다(번호가 작을수록 우선). */
  li   t0, -1
  csrw pmpaddr7, t0
  li   t0, (0x1f << 56)          /* pmpcfg0[63:56] = A=NAPOT(3), X W R = 1 */
  csrw pmpcfg0, t0

  /* mstatus.FS = Initial (FP 명령 사용 가능) */
  li   t0, (1 << 13)
  csrs mstatus, t0

  /* I$, D$, BHT, BTB 무효화 : MCOR = {btb_inv(17), bht_inv(16), .., inv(4), .., sel[1:0]=11} */
  li   t0, (1 << 17) | (1 << 16) | (1 << 4) | 0x3
  csrw CSR_MCOR, t0
1:
  csrr t0, CSR_MCOR
  li   t1, (1 << 17) | (1 << 16) | (1 << 4)
  and  t0, t0, t1
  bnez t0, 1b                    /* 하드웨어가 완료 시 비트를 0 으로 만든다 */

  li   t0, MHCR_DEFAULT
  csrw CSR_MHCR, t0
  csrw CSR_MHINT, zero           /* prefetch off */

  /* HPM */
  csrw mcountinhibit, zero
  li   t0, HPM_BR_MISPRED
  csrw mhpmevent3, t0
  li   t0, HPM_BR_COND
  csrw mhpmevent4, t0
  li   t0, HPM_IC_MISS
  csrw mhpmevent5, t0
  li   t0, HPM_DC_RD_ACC
  csrw mhpmevent6, t0
  li   t0, HPM_DC_RD_MISS
  csrw mhpmevent7, t0
  li   t0, HPM_FE_STALL
  csrw mhpmevent8, t0
  li   t0, HPM_BE_STALL
  csrw mhpmevent9, t0

  jal  ra, main
  j    pass

/* ------------------------------------------------------------------ PASS/FAIL
 * tb.v 는 write-back 데이터가 0x444333222 이면 PASS, 0x2382348720 이면 FAIL 로 종료 */
  .globl pass
pass:
  PRINT "[study] PASS\n"
  li   x3, 0x444333222
1: j 1b

  .globl fail
fail:
  csrr s0, mepc
  PRINT "[study] FAIL\n"
  li   x3, 0x2382348720
1: j 1b

/* ------------------------------------------------------------------ trap
 * mtvec(direct) -> 여기 -> 테스트가 정의한 trap_handler (없으면 __default_trap) */
  .align 6
  .globl __trap_entry
__trap_entry:
  j    trap_handler

  .weak trap_handler
  .globl __default_trap
trap_handler:
__default_trap:
  csrr s0, mcause
  csrr s1, mepc
  csrr s2, mtval
  REPORT "unexpected_trap_mcause", s0
  REPORT "unexpected_trap_mepc", s1
  REPORT "unexpected_trap_mtval", s2
  j    fail
