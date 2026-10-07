# ============================================================================
# u00_smoke : 유닛 테스트 환경 동작 확인 (출력 / mcycle / mark / PASS)
# GTKW: fe id ex rt
# ============================================================================
#include "study.h"

  .text
  .globl main
main:
  PRINT "[u00] hello from C906\n"

  MARK(1)
  TIC(s0)
  li   a0, 1
  addi a0, a0, 1
  addi a0, a0, 1
  addi a0, a0, 1
  TOC(s0)
  MARK(0)
  EXPECT a0, 4
  REPORT "four_addi_cycles", s0

  # 정보 CSR : misa = MXL(63:62) | 확장 비트(25:0, A=bit0 ... Z=bit25)
  csrr s1, misa
  REPORT "misa_hex_as_dec", s1
  li   t1, 0x3ffffff
  and  s2, s1, t1
  REPORT "misa_ext_bits", s2
  srli s3, s1, 21                # bit 21 = 'V'
  andi s3, s3, 1
  REPORT "misa_V(vector)", s3
  csrr s4, mvendorid
  REPORT "mvendorid", s4
  csrr s5, marchid
  REPORT "marchid", s5
  csrr s6, mimpid
  REPORT "mimpid", s6
  csrr s7, mhartid
  REPORT "mhartid", s7
  j    pass
