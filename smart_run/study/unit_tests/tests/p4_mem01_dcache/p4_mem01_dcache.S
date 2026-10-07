# ============================================================================
# p4_mem01_dcache : D-Cache hit/miss, line fill(AXI burst), 교체 정책, prefetch, write-allocate
#
#  D-Cache : 32KB, 4-way, 64B line, write-back, FIFO 교체 (datasheet)
#            tag index = addr[11:6] (aq_dcache_tag_array.v), 뱅크/앨리어스 처리로 addr[12] 까지 같은
#            따라서 addr[12:6] 이 같은 (8KB 간격) 주소들이 같은 4-way 집합을 놓고 경쟁 -> 5 개로 교체 정책 확인
#
#  [SoC 메모리 지연 모델] smart_run 의 axi_fifo 는 0x0~0x1FFFF 읽기를 bus_delay 레지스터
#  (APB 0x1001A000, 기본 0) 만큼 지연시킨다. 그 밖의 주소는 free-running 카운터 때문에
#  0~200 사이클의 가변 지연이 생기므로, 이 테스트는 0x10000~0x1FFFF 를 버퍼로 쓴다.
#
#  MARK 1 : miss (처음 접근)       MARK 2 : hit (같은 line)
#  MARK 3 : 교체 정책 판별 - A0..A3 채우기 -> A0 재사용 -> A4 (교체 발생) -> A0, A1 재접근
#           FIFO 면 A0 가 쫓겨나고(miss) A1 은 남는다(hit). LRU 면 반대.
#  MARK 4/5 : 64 line 순차 load, bus_delay=0   prefetch OFF / ON
#  MARK 6/7 : 64 line 순차 load, bus_delay=100 prefetch OFF / ON
#  MARK 8/9 : 64 line store, write-allocate ON / OFF -> 다시 load 할 때 hit/miss
# GTKW: lsu rt bus
# ============================================================================
#include "study.h"

#define LINES      64
#define BUS_DELAY  0x1001A000
#define BUF_MISS   0x1C000
#define BUF_WALK0  0x1A000
#define BUF_WALK1  0x1B000
#define BUF_WALK2  0x14000
#define BUF_WALK3  0x15000
#define BUF_ST_WA  0x1D000
#define BUF_ST_NWA 0x1E000
#define CONFLICT   0x10100          /* + k*0x2000 (k=0..4), 같은 set */

.macro HPM_BEGIN
  csrr s3, mhpmcounter6
  csrr s4, mhpmcounter7
.endm
.macro HPM_END
  csrr t1, mhpmcounter6
  sub  s3, t1, s3
  csrr t1, mhpmcounter7
  sub  s4, t1, s4
.endm
/* 한 번의 load 를 측정해서 reg 에 사이클 저장 */
.macro TIME_LD reg, addr
  li   t2, \addr
  TIC(\reg)
  ld   a4, 0(t2)
  TOC(\reg)
.endm

  .text
  .option norvc
  .globl main
main:
  # ------------------------------------------------ MARK 1/2 : miss vs hit
  MARK(1)
  TIME_LD s0, BUF_MISS
  MARK(2)
  TIME_LD s1, BUF_MISS + 8
  MARK(0)
  REPORT "load_miss_cycles", s0
  REPORT "load_hit_cycles", s1

  # ------------------------------------------------ MARK 3 : replacement policy
  MARK(3)
  TIME_LD s0, CONFLICT + 0*0x2000      # A0 miss
  TIME_LD s0, CONFLICT + 1*0x2000      # A1 miss
  TIME_LD s0, CONFLICT + 2*0x2000      # A2 miss
  TIME_LD s0, CONFLICT + 3*0x2000      # A3 miss  -> 4-way 가득
  TIME_LD s5, CONFLICT + 0*0x2000      # A0 hit (LRU 라면 A0 가 '최근' 이 됨)
  TIME_LD s6, CONFLICT + 4*0x2000      # A4 miss -> 하나를 쫓아냄
  TIME_LD s7, CONFLICT + 0*0x2000      # A0 : FIFO=miss / LRU=hit
  TIME_LD s8, CONFLICT + 1*0x2000      # A1 : FIFO=hit  / LRU=miss
  MARK(0)
  REPORT "conflict_A0_reuse_cycles", s5
  REPORT "conflict_A4_cycles", s6
  REPORT "conflict_A0_after_A4_cycles", s7
  REPORT "conflict_A1_after_A4_cycles", s8

  # ------------------------------------------------ MARK 4/5 : walk, delay 0
  li   a0, 0
  jal  ra, set_bus_delay
  csrw CSR_MHINT, zero
  li   s9, BUF_WALK0
  MARK(4)
  jal  ra, timed_walk
  MARK(0)
  REPORT "walk_d0_pf_off_cycles", s0
  REPORT "walk_d0_pf_off_rd_miss", s4
  li   t0, MHINT_DPLD
  csrw CSR_MHINT, t0
  li   s9, BUF_WALK1
  MARK(5)
  jal  ra, timed_walk
  MARK(0)
  csrw CSR_MHINT, zero
  REPORT "walk_d0_pf_on_cycles", s0
  REPORT "walk_d0_pf_on_rd_miss", s4

  # ------------------------------------------------ MARK 6/7 : walk, delay 100
  li   a0, 100
  jal  ra, set_bus_delay
  REPORT "bus_delay_readback", a1
  li   s9, BUF_WALK2
  MARK(6)
  jal  ra, timed_walk
  MARK(0)
  REPORT "walk_d100_pf_off_cycles", s0
  REPORT "walk_d100_pf_off_rd_miss", s4
  li   t0, MHINT_DPLD
  csrw CSR_MHINT, t0
  li   s9, BUF_WALK3
  MARK(7)
  jal  ra, timed_walk
  MARK(0)
  csrw CSR_MHINT, zero
  REPORT "walk_d100_pf_on_cycles", s0
  REPORT "walk_d100_pf_on_rd_miss", s4
  li   a0, 0
  jal  ra, set_bus_delay

  # ------------------------------------------------ MARK 8 : store, write-allocate ON
  SET_MHCR(MHCR_DEFAULT)
  li   s9, BUF_ST_WA
  MARK(8)
  TIC(s0)
  jal  ra, store_walk
  TOC(s0)
  jal  ra, timed_walk
  MARK(0)
  REPORT "store_wa_on_cycles", s0
  REPORT "reload_after_wa_on_rd_miss", s4

  # ------------------------------------------------ MARK 9 : store, write-allocate OFF
  SET_MHCR(MHCR_DEFAULT & ~MHCR_WA)
  li   s9, BUF_ST_NWA
  MARK(9)
  TIC(s0)
  jal  ra, store_walk
  TOC(s0)
  jal  ra, timed_walk
  MARK(0)
  SET_MHCR(MHCR_DEFAULT)
  REPORT "store_wa_off_cycles", s0
  REPORT "reload_after_wa_off_rd_miss", s4
  j    pass

# ----------------------------------------------------------------------------
# timed_walk : s9 부터 64B 간격 LINES 번 load. s0=사이클, s3=read access, s4=read miss
# ----------------------------------------------------------------------------
  .balign 64
timed_walk:
  HPM_BEGIN
  TIC(s0)
  mv   t1, s9
  li   t2, LINES
1:
  ld   a4, 0(t1)
  addi t1, t1, 64
  addi t2, t2, -1
  bnez t2, 1b
  TOC(s0)
  HPM_END
  ret

  .balign 64
store_walk:
  mv   t1, s9
  li   t2, LINES
1:
  sd   t2, 0(t1)
  addi t1, t1, 64
  addi t2, t2, -1
  bnez t2, 1b
  ret

# ----------------------------------------------------------------------------
# set_bus_delay(a0) : SoC 의 bus_delay 레지스터(APB)를 쓴다. a1 = 읽어 본 값
#   0x1001A000 은 sysmap 상 cacheable 이라 D-Cache 를 잠시 끄고(MHCR.DE=0) 버스로 직접 접근한다.
# ----------------------------------------------------------------------------
  .balign 64
set_bus_delay:
  csrci CSR_MHCR, MHCR_DE
  li   t0, BUS_DELAY
  sw   a0, 0(t0)
  fence
  lw   a1, 0(t0)
  csrsi CSR_MHCR, MHCR_DE
  ret
