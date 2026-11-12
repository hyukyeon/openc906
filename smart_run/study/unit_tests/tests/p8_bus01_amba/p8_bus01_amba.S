# ============================================================================
# p8_bus01_amba : AXI / AHB / APB 의 실제 핸드셰이크를 파형으로 본다 (Phase 8 의 2 절)
#
#  MARK 1 : 캐시 가능한 load miss        -> AXI AR(WRAP, len 3) + R 4 beat
#  MARK 2 : D-Cache 끄고 SRAM sw / lw     -> AXI AW + W + B (1 beat), AR + R (1 beat)
#  MARK 3 : D-Cache 끄고 bus_delay 에 sw, lw -> AXI -> axi2ahb -> AHB -> APB (setup, access) 쓰기와 읽기
#           store 는 retire 뒤 BIU 가 내보내므로 버스 쓰기는 sw 보다 몇 사이클 늦게 보인다.
#           0x1001A000 은 0x0~0x1FFFF 밖이라 AR 이 axi_fifo 에서 0~200 cycle 기다린다
#  MARK 4 : PLIC 우선순위 레지스터 sw / lw -> CPU 내부 APB (BIU apbif). AXI 에는 아무것도 안 나간다
#
#  0x10000~0x1FFFF 는 axi_fifo 의 지연이 bus_delay 값(기본 0)으로 고정되는 구간이라 파형이 매번 같다.
# GTKW: axi ahb apb
# ZOOM: mark
# ============================================================================
#include "study.h"

#define BUF_LINE   0x10000          /* MARK 1 : 캐시 라인 하나 (64B) */
#define BUF_UNC    0x10040          /* MARK 2 : D-Cache 끄고 쓰는 word */
#define BUS_DELAY  0x1001A000       /* SoC APB PS8 */

  .text
  .globl main
main:
  # ---------------------------------------------------------------- MARK 1
  li   s1, BUF_LINE
  MARK(1)
  ld   t1, 8(s1)                  # miss -> WRAP 버스트, 요청한 beat(+8 이 들어 있는 0번)부터
  addi t1, t1, 0
  MARK(0)

  # ---------------------------------------------------------------- MARK 2
  li   s2, BUF_UNC
  li   s3, 0x12345678
  csrci CSR_MHCR, MHCR_DE
  MARK(2)
  sw   s3, 0(s2)
  fence
  lw   s4, 0(s2)
  addi s4, s4, 0
  MARK(0)
  csrsi CSR_MHCR, MHCR_DE
  bne  s4, s3, fail

  # ---------------------------------------------------------------- MARK 3
  li   s5, BUS_DELAY
  li   s6, 2
  csrci CSR_MHCR, MHCR_DE
  MARK(3)
  sw   s6, 0(s5)
  fence
  lw   s7, 0(s5)
  addi s7, s7, 0
  MARK(0)
  csrsi CSR_MHCR, MHCR_DE
  EXPECT s7, 2

  # ---------------------------------------------------------------- MARK 4
  li   s8, PLIC_PRIO(TB_IRQ0_ID)
  li   s9, 3
  MARK(4)
  sw   s9, 0(s8)
  fence
  lw   s10, 0(s8)
  addi s10, s10, 0
  MARK(0)
  EXPECT s10, 3
  sw   zero, 0(s8)

  csrci CSR_MHCR, MHCR_DE
  sw   zero, 0(s5)                # bus_delay 를 원래 값 0 으로 (MARK 밖에서)
  fence
  lw   t0, 0(s5)
  csrsi CSR_MHCR, MHCR_DE

  REPORT "uncached_sram_readback", s4
  REPORT "bus_delay_readback", s7
  REPORT "plic_prio35_readback", s10
  j    pass
