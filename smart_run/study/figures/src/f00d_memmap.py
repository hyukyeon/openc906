"""f00d_memmap.png : 유닛 테스트 SoC 의 물리 메모리 맵 (Phase 1 §5.3).
   근거: logical/axi/axi_interconnect128.v (SRAM/APB/ERR 디코드), ahb/ahb.v, apb/apb_bridge.v + apb/apb.v (PS 슬롯),
         axi/axi_slave128.v (L/H = addr[23]), biu/rtl/aq_biu_req_arbiter.v + aq_biu_apbif.v (CPU 내부 APB 디코드),
         unit_tests/common/linker.ld, study.h"""
from _draw import *

fig, ax = canvas(14, 12.5)
ax.text(50, 92.2, "OpenC906 유닛 테스트 SoC 메모리 맵 (40bit 물리 주소)", ha="center", fontsize=15, fontweight="bold")
ax.text(50, 89.8, "위가 높은 주소. 상자 높이는 크기 비례가 아님. 색 = 접근 경로", ha="center", fontsize=9.5, color="#666")

HDR = 86.6
for x, t, ha in [(20.5, "주소 범위", "right"), (40, "영역", "center"), (61, "누가 · 어떤 경로로 접근하나", "left")]:
    ax.text(x, HDR, t, fontsize=11, fontweight="bold", ha=ha, va="center", color="#333")
line(ax, [(1, HDR - 1.6), (99, HDR - 1.6)], color="#999", lw=0.8)

#  (시작, 끝, 제목, 부제, 색, 높이, 경로 설명)
SEG = [
 ("0x00_0000_0000", "0x00_0000_7FFF", ".text · .rodata  (명령 32KB)",
  "inst.pat 적재 · crt0 → main · trap 벡터", BLUE, 8.0,
  "IFU(I-Cache) 명령 fetch, LSU 상수 읽기\n→ BIU → AXI → interconnect → SRAM   · sysmap R0 (캐시 가능)"),
 ("0x00_0000_8000", "0x00_0003_FFFF", "TEXT 영역의 나머지",
  "TB 장치 0x1_FFC0~0x1_FFDF · int_flag 0x1_FFE0", BLUE, 8.0,
  "LSU store 를 테스트벤치가 감시 (IRQ 주입 · 플래그)\n0x0~0x1_FFFF 읽기는 axi_fifo 가 bus_delay 값만큼 지연"),
 ("0x00_0004_0000", "0x00_0007_FFFF", ".data · .bss · 스택  (256KB)",
  "data.pat 적재 · 스택 top 0x7_FFF0 · Sv39 페이지 테이블", BLUE, 9.0,
  "LSU load/store, MMU PTW(페이지 테이블 읽기)\n→ D-Cache → BIU → AXI → SRAM   · sysmap R0 (캐시 가능)"),
 ("0x00_0008_0000", "0x00_00FF_FFFF", "SRAM 나머지 (유닛 테스트 미사용)",
  "SRAM L = 0x0~0x7F_FFFF · H = 0x80_0000~0xFF_FFFF (각 8MB)", BLUE, 6.5,
  "axi_slave128 이 addr[23] 으로 L/H 두 SRAM 중 하나를 고른다"),
 ("0x00_0100_0000", "0x00_0FFF_FFFF", "미매핑", "", GRAY, 4.6,
  "axi_err128 (ERR1): 이름과 달리 OKAY 응답\n읽으면 0, 쓰기는 버려짐 → 버스 에러 예외 없음"),
 ("0x00_1000_0000", "0x00_1FFF_FFFF", "SoC 주변장치  (AXI → AHB → APB)",
  "0x1001_0000 intc · 0x1001_1000 timer · 0x1001_5000 UART\n"
  "0x1001_7000 clkgen · 0x1001_8000 stimer · 0x1001_9000 GPIO\n"
  "0x1001_A000 bus_delay · 0x1F00_0000 AHB RAM (mem_ctrl)", PURP, 13.0,
  "LSU → BIU → AXI → axi2ahb → AHB → APB bridge\n"
  "sysmap R0 = 캐시 가능 → D-Cache 를 끄고(MHCR.DE=0) 써야 버스로 나감\n"
  "(그래서 유닛 테스트 콘솔은 UART 대신 mscratch 를 쓴다)"),
 ("0x00_2000_0000", "0x3F_FFFF_FFFF", "미매핑", "", GRAY, 4.6,
  "axi_err128 (ERR2): OKAY 응답 · 읽기 0 · 쓰기 무시"),
 ("0x40_0000_0000", "0x40_07FF_FFFF", "CPU 내부 APB  (pad_cpu_apb_base, 128MB 창)", "", GREEN, 12.0,
  "LSU → BIU 의 apbif 가 주소 [39:27] 비교로 가로챈다\n→ AXI 로 나가지 않는다   · sysmap R6 (장치, 캐시 불가)\n"
  "PLIC: claim/complete · CLINT: MSIP · mtimecmp"),
 ("0x40_0800_0000", "0xFF_FFFF_FFFF", "미매핑", "", GRAY, 4.6,
  "axi_err128 (ERR2): OKAY 응답 · 읽기 0 · 쓰기 무시"),
]

y = 6.0; GAP = 0.8
BX0, BX1 = 22.0, 58.5
for s, e, title, sub, c, h, path in SEG:
    box(ax, BX0, y, BX1 - BX0, h, c, r=0.6)
    ax.text(20.5, y + h - 1.0, e, ha="right", va="top", fontsize=9.3, family=MONO, color="#333")
    ax.text(20.5, y + 0.9, s, ha="right", va="bottom", fontsize=9.3, family=MONO, color="#333")
    cx = (BX0 + BX1) / 2
    if title.startswith("CPU 내부 APB"):
        ax.text(cx, y + h - 1.6, title, ha="center", va="center", fontsize=11, fontweight="bold")
        tbox(ax, cx - 8.6, y + 4.3, 16.4, 6.6, "PLIC",
             "0x40_0000_0000\n~ 0x40_03FF_FFFF", GREEN, ts=11, ss=8.6, r=0.5)
        tbox(ax, cx + 8.6, y + 4.3, 16.4, 6.6, "CLINT",
             "0x40_0400_0000\n~ 0x40_0400_FFFF", GREEN, ts=11, ss=8.6, r=0.5)
    elif sub:
        nl = sub.count("\n")
        ax.text(cx, y + h - 1.7, title, ha="center", va="center", fontsize=11, fontweight="bold")
        ax.text(cx, y + (h - 3.0) / 2, sub, ha="center", va="center", fontsize=8.8 if nl else 9,
                color="#333", linespacing=1.45)
    else:
        ax.text(cx, y + h / 2, title, ha="center", va="center", fontsize=10.5, color="#777")
    ax.text(61, y + h / 2, path, ha="left", va="center", fontsize=8.8, color="#333", linespacing=1.45)
    y += h + GAP

# 범례
ly = 1.6
for i, (c, t) in enumerate([(BLUE, "SRAM (AXI → axi_slave128)"), (PURP, "SoC 주변장치 (AXI → AHB → APB)"),
                            (GREEN, "CPU 내부 APB (BIU 가 가로챔)"), (GRAY, "미매핑 (axi_err128, OKAY 응답)")]):
    x = 2 + i * 24.5
    box(ax, x, ly - 1.0, 3.2, 2.0, c, r=0.3)
    ax.text(x + 4.0, ly, t, va="center", fontsize=9.3)

save(fig, "f00d_memmap.png")
