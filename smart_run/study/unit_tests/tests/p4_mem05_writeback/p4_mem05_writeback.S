# ============================================================================
# p4_mem05_writeback : D-Cache dirty 라인 교체 -> victim buffer(VB) 의 AXI 쓰기 버스트
#
#  D-Cache 는 write-back + write-allocate(MHCR.WA). store miss 는 라인을 읽어 와서(refill) 고친다 -> dirty.
#  같은 set(addr[12:6]) 에 5 번째 라인이 들어오면 FIFO 로 가장 먼저 들어온 라인이 쫓겨나고,
#  그 라인이 dirty 면 VB 가 64B 를 AXI 쓰기 버스트(awlen = 3, INCR)로 메모리에 쓴다 (aq_lsu_vb.v:463-468).
#
#  MARK 1 : set A 의 4 way 에 store (8KB 간격)  -> refill(AR WRAP) 4 번, AW 없음. 라인 4 개 dirty
#  MARK 2 : set A 에 5 번째 라인 load          -> dirty A0 교체 : AW 4 beat(write-back) + AR(refill)
#  MARK 3 : set B (clean 라인 4 개) 에 5 번째 load -> clean 교체 : AR 만, AW 없음
#  MARK 4 : th.dcache.cva A1 (T-Head 캐시 명령)  -> 교체 없이 dirty 라인만 메모리로 : AW 4 beat
#  검증 : D-Cache 를 끄고 메모리를 직접 읽어 A0(교체로), A1(cva 로) 의 값이 메모리에 써졌는지 확인한다.
#
#  0x10000~0x1FFFF 는 axi_fifo 지연이 bus_delay(0) 로 고정되는 구간이라 사이클이 매번 같다.
# GTKW: lsu bus axi
# ZOOM: mark
# ============================================================================
#include "study.h"
  .option arch, +xtheadcmo, +xtheadsync

#define SET_A    0x10000        /* addr[12:6] = 0 */
#define SET_B    0x10040        /* addr[12:6] = 1 */
#define STRIDE   0x2000         /* 8KB : 같은 set, 다른 tag */

  .text
  .globl main
main:
  li   s1, SET_A
  li   s2, STRIDE

  # ---------------------------------------------------------------- MARK 1
  MARK(1)
  TIC(s0)
  li   t2, 0xA0
  sd   t2, 8(s1)                  # A0
  add  t3, s1, s2
  li   t2, 0xA1
  sd   t2, 8(t3)                  # A1
  add  t3, t3, s2
  li   t2, 0xA2
  sd   t2, 8(t3)                  # A2
  add  t3, t3, s2
  li   t2, 0xA3
  sd   t2, 8(t3)                  # A3
  fence
  TOC(s0)
  MARK(0)
  REPORT "m1_four_store_miss_cycles", s0

  # ---------------------------------------------------------------- MARK 2
  slli t3, s2, 2
  add  s3, s1, t3                 # A4 = A0 + 4 * 8KB
  MARK(2)
  TIC(s0)
  ld   t1, 0(s3)
  addi t1, t1, 0
  TOC(s0)
  MARK(0)
  REPORT "m2_dirty_evict_load_cycles", s0

  # ---------------------------------------------------------------- MARK 3
  li   s4, SET_B
  ld   t1, 0(s4)                  # B0~B3 : clean 라인으로 채운다
  add  t3, s4, s2
  ld   t1, 0(t3)
  add  t3, t3, s2
  ld   t1, 0(t3)
  add  t3, t3, s2
  ld   t1, 0(t3)
  addi t1, t1, 0
  slli t3, s2, 2
  add  s5, s4, t3                 # B4
  MARK(3)
  TIC(s0)
  ld   t1, 0(s5)
  addi t1, t1, 0
  TOC(s0)
  MARK(0)
  REPORT "m3_clean_evict_load_cycles", s0

  # ---------------------------------------------------------------- MARK 4
  add  s6, s1, s2                 # A1 (아직 캐시에 dirty 로 남아 있다)
  MARK(4)
  TIC(s0)
  th.dcache.cva s6
  th.sync                        # cache 명령이 끝날 때까지 기다린다 (fence 는 기다리지 않는다)
  TOC(s0)
  MARK(0)
  REPORT "m4_dcache_cva_cycles", s0

  # ---------------------------------------------------------------- 검증
  csrci CSR_MHCR, MHCR_DE
  ld   s7, 8(s1)                  # A0 : 교체로 write-back 된 값
  ld   s8, 8(s6)                  # A1 : cva 로 clean 된 값
  csrsi CSR_MHCR, MHCR_DE
  EXPECT s7, 0xA0
  EXPECT s8, 0xA1
  REPORT "mem_A0_after_evict", s7
  REPORT "mem_A1_after_cva", s8
  j    pass
