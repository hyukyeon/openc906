"""f00b_memmap.png : 물리 주소 영역과 MMU sysmap 속성 (Phase 1 §5.3). 실행: ~/06_Notion/venv/bin/python f00b_memmap.py
   영역 경계: C906_RTL_FACTORY/gen_rtl/mmu/rtl/sysmap.h (BASE_ADDRi 는 4KB 페이지 번호, 영역 i = [BASE_{i-1}, BASE_i) )
   속성 비트 순서: aq_mmu_regs.v 의 mel_so/c/b/sh/sec = pma[4:0] 대응 (SO, C, B, SH, SEC)"""
import os
import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
from matplotlib import font_manager
from matplotlib.patches import FancyBboxPatch

for f in font_manager.findSystemFonts():
    if "wqy-zenhei" in f.lower():
        font_manager.fontManager.addfont(f)
plt.rcParams["font.family"] = ["WenQuanYi Zen Hei", "DejaVu Sans"]

CACHE = ("#eef3fb", "#4a6fa5", "일반 메모리 · 캐시 가능")
DEV   = ("#fff6e5", "#c08a2a", "장치(Strongly-ordered)")
NC    = ("#f3f3f3", "#888888", "일반 메모리 · 캐시 불가")

# (영역, 시작, 끝(포함), 플래그, 종류, 내용)
ROWS = [
 ("R0", "0x00_0000_0000", "0x00_8FFF_EFFF", "01111", CACHE,
  "SRAM 0x0000_0000~ (SoC 버스)\nAPB 0x1000_0000~ (UART 0x1001_5000)"),
 ("R1", "0x00_8FFF_F000", "0x00_BFFF_EFFF", "10011", DEV,  "SoC 맵에 기록 없음 (미확인)"),
 ("R2", "0x00_BFFF_F000", "0x00_CFFF_EFFF", "00011", NC,   "SoC 맵에 기록 없음 (미확인)"),
 ("R3", "0x00_CFFF_F000", "0x00_EFFF_EFFF", "01101", CACHE, "SoC 맵에 기록 없음 (미확인)"),
 ("R4", "0x00_EFFF_F000", "0x00_FFFF_EFFF", "01111", CACHE, "SoC 맵에 기록 없음 (미확인)"),
 ("R5", "0x00_FFFF_F000", "0x3F_FFFF_EFFF", "01111", CACHE, "외부 메모리 후보 영역 (미확인)"),
 ("R6", "0x3F_FFFF_F000", "0x4F_FFFF_EFFF", "10010", DEV,
  "CPU 내부 APB\nPLIC · CLINT"),
 ("R7", "0x4F_FFFF_F000", "0xFF_FFFF_EFFF", "01111", CACHE, "SoC 맵에 기록 없음 (미확인)"),
]

fig, ax = plt.subplots(figsize=(14, 8.6))
ax.set_xlim(0, 100); ax.set_ylim(0, 100); ax.axis("off")
ax.text(50, 98.0, "OpenC906 물리 주소 영역 (MMU sysmap, 40bit PA)", ha="center", fontsize=15, fontweight="bold")
ax.text(50, 95.2, "주소 상자는 크기 비례가 아니라 순서대로 나열. 같은 색 = 같은 속성",
        ha="center", fontsize=9.5, color="#666")

# 열 머리글
hdr_y = 89.0
for x, t in [(2, "영역"), (6, "시작 주소"), (25, "끝 주소 (포함)"), (44, "플래그 SO C B SH SEC"), (60, "속성"), (75, "들어 있는 것")]:
    ax.text(x, hdr_y, t, fontsize=11, fontweight="bold", va="center", color="#333")
ax.plot([1, 99], [hdr_y - 1.6, hdr_y - 1.6], color="#999", lw=0.8)

top, step, h = 81.0, 9.9, 8.2
for i, (name, s, e, flg, (fc, ec, kind), who) in enumerate(ROWS):
    y = top - i * step
    ax.add_patch(FancyBboxPatch((1, y - h / 2), 98, h, boxstyle="round,pad=0,rounding_size=0.8",
                                fc=fc, ec=ec, lw=1.2))
    ax.text(2.5, y, name, fontsize=12, fontweight="bold", va="center")
    ax.text(6, y, s, fontsize=10.5, va="center", family="DejaVu Sans Mono")
    ax.text(25, y, e, fontsize=10.5, va="center", family="DejaVu Sans Mono")
    bits = "  ".join(flg)
    ax.text(44, y, bits, fontsize=10.5, va="center", family="DejaVu Sans Mono")
    ax.text(60, y, kind, fontsize=9, va="center", color="#333")
    ax.text(75, y, who, fontsize=8.5, va="center", color="#222", linespacing=1.3)

foot = ("플래그: SO=Strongly Ordered(장치), C=Cacheable, B=Bufferable, SH=Shareable, SEC=Security.  "
        "예) R0 = 01111 → 캐시 가능 일반 메모리.\n"
        "※ R0 의 UART(0x1001_5000) 가 캐시 가능하다는 점이 Phase 1 §5.3 의 주의 사항과 연결된다. "
        "※ 주소 0xFF_FFFF_F000 이상은 sysmap 에 없다.")
ax.text(2, 0.3, foot, fontsize=9.5, color="#444", va="bottom", linespacing=1.5)

out = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "f00b_memmap.png")
fig.savefig(out, dpi=150, bbox_inches="tight", facecolor="white")
print(out)
