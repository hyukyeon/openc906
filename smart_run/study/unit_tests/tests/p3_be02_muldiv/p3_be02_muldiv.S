# ============================================================================
# p3_be02_muldiv : 곱셈기/나눗셈기 latency
#
#  aq_iu_mul.v : Booth radix-4 (booth_code_33_bit) 기반, 결과는 EX3 에서 write-back
#                (iu_rtu_ex3_mul_*) -> 의존 체인 latency 측정
#  aq_iu_div.v : 반복형 나눗셈기. 피연산자 값에 따라 사이클이 달라진다(UM: 2~36)
#                + 직전 연산과 피연산자(값/부호/word)가 같으면 결과 버퍼에서 바로 응답
#                  (div_hit_buffer, aq_iu_div.v:779) -> div 다음 같은 피연산자의 rem 은 거의 공짜
#                + 0 으로 나누기 / 피제수 0 / overflow 는 반복 없이 즉시(abnormal) 처리
#  측정 주의: csrr mcycle(TOC)은 CP0 명령이라 ID 에서 "파이프라인이 빌 때까지" 대기한다
#            (aq_idu_id_ctrl.v ctrl_dis_cp0_stall). 따라서 TOC 는 앞선 div 완료를 기다린다.
#
#  MARK 1 : mul 의존 체인 x16            -> latency
#  MARK 2 : mul 독립 x16                 -> throughput
#  MARK 3 : mulh 의존 체인 x16
#  MARK 4 : mulw 의존 체인 x16
#  MARK 10.. : divu/div 한 번, 피연산자 조합별 사이클 (직전에 다른 피연산자로 한 번 실행해 버퍼 miss 유도)
#  MARK 30  : divu 다음 같은 피연산자 remu (결과 버퍼 hit)
# GTKW: id ex rt
# ============================================================================
#include "study.h"

.macro DIV1 mark, op, a, b, name
  li   a4, \a
  li   a5, \b
  addi t3, a4, 1
  \op  a6, t3, a5                # 다른 피연산자로 먼저 한 번 -> 결과 버퍼 miss 유도
  MARK(\mark)
  TIC(s0)
  \op  a6, a4, a5
  TOC(s0)                        # (TOC 의 csrr 이 div 완료까지 기다림)
  MARK(0)
  REPORT "\name", s0
.endm

  .text
  .option norvc
  .globl main
main:
  li   a2, 1
  li   a3, 3

  jal  ra, mul_chain
  MARK(1)
  jal  ra, mul_chain
  MARK(0)
  REPORT "mul_chain_x16", s0

  jal  ra, mul_indep
  MARK(2)
  jal  ra, mul_indep
  MARK(0)
  REPORT "mul_indep_x16", s0

  jal  ra, mulh_chain
  MARK(3)
  jal  ra, mulh_chain
  MARK(0)
  REPORT "mulh_chain_x16", s0

  jal  ra, mulw_chain
  MARK(4)
  jal  ra, mulw_chain
  MARK(0)
  REPORT "mulw_chain_x16", s0

  # 기준: addi 하나
  li   a4, 1
  MARK(9)
  TIC(s0)
  addi a6, a4, 1
  TOC(s0)
  MARK(0)
  REPORT "baseline_addi", s0

  DIV1 10, divu, -1, 3,          divu_max_by_3
  DIV1 11, divu, 1000, 3,        divu_1000_by_3
  DIV1 12, divu, 7, 7,           divu_7_by_7
  DIV1 13, divu, 3, 7,           divu_3_by_7
  DIV1 14, divu, 0x123456789, 1, divu_x_by_1
  DIV1 15, divu, 5, 0,           divu_by_zero
  DIV1 16, div,  -1000, 3,       div_neg1000_by_3
  DIV1 17, divw, 1000, 3,        divw_1000_by_3
  DIV1 18, remu, -1, 3,          remu_max_by_3
  DIV1 19, divu, 0, 3,           divu_zero_by_3
  DIV1 20, div,  0x8000000000000000, -1, div_overflow
  DIV1 21, divu, 0x7fffffffffffffff, 0x7ffffffffffffffe, divu_big_by_big

  # ------------------------------------------------ MARK 30 : div + rem 같은 피연산자
  li   a4, 1000003
  li   a5, 17
  addi t3, a4, 1
  divu a6, t3, a5
  MARK(30)
  TIC(s0)
  divu a6, a4, a5
  remu a7, a4, a5                # 결과 버퍼 hit
  TOC(s0)
  MARK(0)
  REPORT "divu_then_remu_same_operands", s0
  li   a4, 1000003
  li   a5, 17
  addi t3, a4, 1
  divu a6, t3, a5
  MARK(31)
  TIC(s0)
  divu a6, a4, a5
  TOC(s0)
  MARK(0)
  REPORT "divu_alone_same_operands_as_30", s0
  j    pass

# ----------------------------------------------------------------------------
  .balign 64
mul_chain:
  li   a4, 7
  TIC(s0)
  .rept 16
  mul  a4, a4, a2                # a4 = a4 * 1 : 직전 결과에 의존
  .endr
  TOC(s0)
  ret

  .balign 64
mul_indep:
  TIC(s0)
  .rept 4
  mul  a4, a2, a3
  mul  a5, a2, a3
  mul  a6, a2, a3
  mul  a7, a2, a3
  .endr
  TOC(s0)
  ret

  .balign 64
mulh_chain:
  li   a4, 7
  TIC(s0)
  .rept 16
  mulh a4, a4, a3
  .endr
  TOC(s0)
  ret

  .balign 64
mulw_chain:
  li   a4, 7
  TIC(s0)
  .rept 16
  mulw a4, a4, a2
  .endr
  TOC(s0)
  ret
