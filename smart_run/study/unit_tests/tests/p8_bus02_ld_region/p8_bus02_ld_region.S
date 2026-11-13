# ============================================================================
# p8_bus02_ld_region : 메모리 맵의 영역마다 scalar load 가 되는지, 몇 사이클 걸리는지
#
#  모든 측정은 같은 함수(ld_probe / lw_probe)로 한다. 함수 코드는 미리 한 번 불러 I-Cache 에 올려 둔다.
#    TIC ; ld s1,0(a2) ; addi s1,s1,0(결과 사용) ; TOC      -> cycles
#  기준(빈 TIC/TOC 와 D-Cache hit)을 빼면 영역별 추가 지연이 나온다.
#  예외가 나면 trap_handler 가 mcause 를 s2 에 남기고 mepc 다음 명령으로 돌아간다(값은 -1 그대로).
#  보고: 예외가 없으면 <name>_cyc, <name>_val(하위 32bit)
#        예외가 나면 <name>_cause(mcause), <name>_epc_off(mepc - load 주소), <name>_trap_entry(TIC 부터 trap 진입까지)
#
#  MARK 1  sram_lo_miss    0x0001_0000  ld  DE=1   SRAM, axi_fifo 지연 = bus_delay(0)
#  MARK 2  sram_lo_hit     0x0001_0000  ld  DE=1   D-Cache hit
#  MARK 3-6 sram_hi_miss_a..d 0x6_0000+n*64 ld DE=1 SRAM, axi_fifo free-running 카운터
#  MARK 7  sram_top_miss   0x0010_0000  ld  DE=1   SRAM 의 나머지 (H 뱅크 아님, L 뱅크 1MB)
#  MARK 8  sram_lo_unc     0x0001_0040  ld  DE=0   캐시 없이 SRAM
#  MARK 9  sram_hi_unc     0x0006_0100  ld  DE=0
#  MARK 10 err1_miss       0x0100_0000  ld  DE=1   미매핑 ERR1 (axi_err128, OKAY)
#  MARK 11 err1_unc        0x0100_0040  ld  DE=0
#  MARK 12 apb_bdly_unc    0x1001_A000  lw  DE=0   SoC APB (AXI -> AHB -> APB)
#  MARK 13 apb_timer_unc   0x1001_1000  lw  DE=0
#  MARK 14 apb_bdly_miss   0x1001_A000  lw  DE=1   주변장치를 캐시로 읽으면 (sysmap R0 = cacheable)
#  MARK 15 apb_bdly_hit    0x1001_A000  lw  DE=1
#  MARK 16 ahb_ram_unc     0x1F00_0000  ld  DE=0   AHB S1 mem_ctrl
#  MARK 17 ahb_ram_miss    0x1F00_0040  ld  DE=1
#  MARK 18 ahb_err_unc     0x1F02_0000  lw  DE=0   AHB 기본 슬레이브 (ERROR 응답)
#  MARK 19 err2_unc        0x2000_0000  ld  DE=0   미매핑 ERR2
#  MARK 20 err2_miss       0x2000_0040  ld  DE=1
#  MARK 21 plic_prio_lw    PLIC_PRIO(35) lw        CPU 내부 APB (R6 device)
#  MARK 22 plic_prio_ld    PLIC_PRIO(34) ld        64bit 로 읽으면 (8B 정렬 주소 0x88)
#  MARK 23 clint_cmp_lw    MTIMECMPL    lw
#  MARK 24 capb_hole_lw    0x40_0401_0000 lw       CPU 내부 APB 창의 빈 곳
#  MARK 25 above_capb_lw   0x40_0800_0000 lw       창 밖 (R6 device, AXI 로 나감)
#  MARK 26 err2_r7_miss    0x50_0000_0000 ld DE=1  sysmap R7 (cacheable) 의 미매핑
#  MARK 27 pa_over40_ld    0x100_0000_0000 ld      40bit 물리 주소를 넘는 주소
#  MARK 28-29 sram_lo_unc_b/c 0x1_00C0, 0x1_0100 ld DE=0  uncached 반복 -> 3 번 모두 16 (arcache[2] 는 DE 가 아니라 sysmap C 에서 오므로 fifo 지연 고정)
#  MARK 30    timer1_cur_unc  timer 1 현재값(0x1001_1004) DE=0 lw -> 0 (load 는 16B 정렬로 나가 0x1001_1000 을 읽는다)
#  MARK 31-33 t1_ist_miss / t1_ist_unc / t1_ist_hit
#             timer 1 int status(0x1001_1010) 를 타이머가 울리기 전에 캐시로 읽고(0), 울린 뒤 버스로(1), 캐시로(0, 옛 값)
# GTKW: id lsu ex axi ahb apb
# ZOOM: mark
# ============================================================================
#include "study.h"

#define BUS_DELAY  0x1001A000
/* SoC timer (common/timer.v) : 채널 1 = 0x00 load / 0x04 현재값 / 0x08 control, 채널 4 = 0x3C / 0x40 / 0x44 */
#define TIMER1_LOAD 0x10011000
#define TIMER1_CUR  0x10011004
#define TIMER1_IST  0x10011010
#define TIMER1_CTRL 0x10011008
#define TIMER4_CUR  0x10011040
#define TIMER4_CTRL 0x10011044

.macro CASE name, mark, addr, fn, de
  .if \de
  csrsi CSR_MHCR, MHCR_DE
  .else
  csrci CSR_MHCR, MHCR_DE
  .endif
  li   a2, \addr
  MARK(\mark)
  call \fn
  MARK(0)
  csrsi CSR_MHCR, MHCR_DE
  bnez s2, .Ltr_\@
  REPORT "\name\()_cyc", s0
  slli s1, s1, 32
  srli s1, s1, 32
  REPORT "\name\()_val", s1
  j    .Lend_\@
.Ltr_\@:
  REPORT "\name\()_cause", s2
  REPORT "\name\()_epc_off", s3
  REPORT "\name\()_trap_entry", s4
.Lend_\@:
.endm

/* DE=0 으로 word 하나를 버스에 직접 쓴다 */
.macro UNC_SW addr, val
  csrci CSR_MHCR, MHCR_DE
  li   t1, \addr
  li   t2, \val
  sw   t2, 0(t1)
  fence
  csrsi CSR_MHCR, MHCR_DE
.endm

  .text
  .option norvc
  .globl main
main:
  # 함수와 trap_handler 를 I-Cache 에 올린다 (주소 0x10080 의 SRAM 라인도 같이)
  li   a2, 0x10080
  call ld_probe
  call lw_probe
  call ld_probe
  call lw_probe
  call empty_probe
  call empty_probe
  REPORT "empty_cyc", s0
  li   a2, 0x10080
  call ld_probe
  REPORT "warm_hit_cyc", s0

  CASE sram_lo_miss,     1, 0x00010000, ld_probe, 1
  CASE sram_lo_hit,      2, 0x00010000, ld_probe, 1
  CASE sram_hi_miss_a,   3, 0x00060000, ld_probe, 1
  CASE sram_hi_miss_b,   4, 0x00060040, ld_probe, 1
  CASE sram_hi_miss_c,   5, 0x00060080, ld_probe, 1
  CASE sram_hi_miss_d,   6, 0x000600C0, ld_probe, 1
  CASE sram_top_miss,    7, 0x00100000, ld_probe, 1
  CASE sram_lo_unc,      8, 0x00010040, ld_probe, 0
  CASE sram_hi_unc,      9, 0x00060100, ld_probe, 0
  CASE err1_miss,       10, 0x01000000, ld_probe, 1
  CASE err1_unc,        11, 0x01000040, ld_probe, 0
  CASE apb_bdly_unc,    12, BUS_DELAY,  lw_probe, 0
  CASE apb_timer_unc,   13, 0x10011000, lw_probe, 0
  CASE apb_bdly_miss,   14, BUS_DELAY,  lw_probe, 1
  CASE apb_bdly_hit,    15, BUS_DELAY,  lw_probe, 1
  CASE ahb_ram_unc,     16, 0x1F000000, ld_probe, 0
  CASE ahb_ram_miss,    17, 0x1F000040, ld_probe, 1
  CASE ahb_err_unc,     18, 0x1F020000, lw_probe, 0
  CASE err2_unc,        19, 0x20000000, ld_probe, 0
  CASE err2_miss,       20, 0x20000040, ld_probe, 1
  CASE plic_prio_lw,    21, PLIC_PRIO(TB_IRQ0_ID), lw_probe, 1
  CASE plic_prio_ld,    22, PLIC_PRIO(34), ld_probe, 1
  CASE clint_cmp_lw,    23, CLINT_MTIMECMPL, lw_probe, 1
  CASE capb_hole_lw,    24, 0x4004010000, lw_probe, 1
  CASE above_capb_lw,   25, 0x4008000000, lw_probe, 1
  CASE err2_r7_miss,    26, 0x5000000000, ld_probe, 1
  CASE pa_over40_ld,    27, 0x10000000000, ld_probe, 1
  # DE=0 이어도 arcache[2] = sysmap C = 1 (aq_lsu_lfb.v:679) -> 0x0~0x1FFFF 면 axi_fifo 지연이 고정인지 반복해서 본다
  CASE sram_lo_unc_b,   28, 0x000100C0, ld_probe, 0
  CASE sram_lo_unc_c,   29, 0x00010100, ld_probe, 0
  # SoC 주변장치 레지스터 정렬 : SO 가 아닌 영역(sysmap R0)은 load 를 16B, store 를 8B 정렬 주소로 낸다
  #   -> ahb2apb 는 그 주소로 APB 접근을 한 번만 하므로 timer 1 현재값(0x1001_1004) 은 0x1001_1000 을 읽는다
  CASE timer1_cur_unc,  30, TIMER1_CUR, lw_probe, 0
  UNC_SW TIMER4_CTRL, 5          # 0x1001_1044 -> AW 0x1001_1040, APB 에는 0x1001_1040 / pwdata 0 으로 간다 (파형)
  # 주변장치를 캐시로 읽으면 옛 값 : timer 1 int status(0x1001_1010, 16B 정렬)를 이용한다
  UNC_SW TIMER1_LOAD, 1000       # user-defined mode 의 시작값
  CASE t1_ist_miss,     31, TIMER1_IST, lw_probe, 1      # 타이머 끄진 상태 -> 0 이 캐시에 들어간다
  UNC_SW TIMER1_CTRL, 3          # enable(bit0) + user-defined mode(bit1), mask 없음 -> 1000 사이클 뒤 status = 1
  # 이 store 는 STB 의 write-combine 상태(STB_MERGE)에 남아 fence 뒤에도 버스로 나가지 않는다.
  # 같은 라인을 읽으면 그때 나간다 (aq_lsu_stb_entry.v:376-377, 422-427 / 실측: MARK 31~32 사이 약 3000 cycle 대기)
  csrci CSR_MHCR, MHCR_DE
  li   t1, TIMER1_LOAD
  lw   t2, 0(t1)
  csrsi CSR_MHCR, MHCR_DE
  li   t1, 1500
1:addi t1, t1, -1
  bnez t1, 1b
  CASE t1_ist_unc,      32, TIMER1_IST, lw_probe, 0      # 버스로 읽음 -> 1
  CASE t1_ist_hit,      33, TIMER1_IST, lw_probe, 1      # 캐시 hit -> 옛 값 0
  UNC_SW TIMER1_CTRL, 0
  j    pass

# ----------------------------------------------------------------------------
  .balign 64
ld_probe:
  li   s2, 0
  li   s1, -1
  la   a3, 1f
  TIC(s0)
1:ld   s1, 0(a2)
  addi s1, s1, 0
  TOC(s0)
  ret

  .balign 64
lw_probe:
  li   s2, 0
  li   s1, -1
  la   a3, 1f
  TIC(s0)
1:lw   s1, 0(a2)
  addi s1, s1, 0
  TOC(s0)
  ret

  .balign 64
empty_probe:
  li   s2, 0
  li   s1, -1
  la   a3, 1f
  TIC(s0)
1:nop
  addi s1, s1, 0
  TOC(s0)
  ret

# trap_handler : s2 = mcause, s3 = mepc - load 주소(a3), s4 = TIC 부터 trap 진입까지 사이클
#   load 를 건너뛰어 mepc+4 로 돌아간다
  .balign 64
  .globl trap_handler
trap_handler:
  csrr s4, mcycle
  sub  s4, s4, s0
  csrr s2, mcause
  csrr t3, mepc
  sub  s3, t3, a3
  addi t3, t3, 4
  csrw mepc, t3
  mret
