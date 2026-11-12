"""f00_core_blocks.png : OpenC906 블록 다이어그램 (Phase 1 §1.2). 실행: python3 f00_core_blocks.py"""
import os
import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
from matplotlib import font_manager
from matplotlib.patches import FancyBboxPatch, FancyArrowPatch

for f in font_manager.findSystemFonts():
    if "wqy-zenhei" in f.lower():
        font_manager.fontManager.addfont(f)
plt.rcParams["font.family"] = ["WenQuanYi Zen Hei", "DejaVu Sans"]

BLUE = ("#eef3fb", "#4a6fa5"); AMBER = ("#fff6e5", "#c08a2a")
GREEN = ("#eaf5ea", "#4a8f4a"); RED = "#c0504d"

fig, ax = plt.subplots(figsize=(14, 8.4))
ax.set_xlim(0, 100); ax.set_ylim(0, 63); ax.axis("off")


def box(cx, cy, w, h, title, sub, c, dashed=False):
    ax.add_patch(FancyBboxPatch((cx - w / 2, cy - h / 2), w, h, boxstyle="round,pad=0,rounding_size=1.2",
                                fc=c[0], ec=c[1], lw=1.6, ls="--" if dashed else "-"))
    ax.text(cx, cy + h * 0.17, title, ha="center", va="center", fontsize=12.5, fontweight="bold", color="#222")
    ax.text(cx, cy - h * 0.20, sub, ha="center", va="center", fontsize=9.5, color="#333", linespacing=1.35)


def arrow(p, q, color="#555", ls="-", both=False, lw=1.6, rad=0.0):
    ax.add_patch(FancyArrowPatch(p, q, arrowstyle="<|-|>" if both else "-|>", mutation_scale=13,
                                 color=color, lw=lw, ls=ls, connectionstyle=f"arc3,rad={rad}", shrinkA=0, shrinkB=0))


def line(pts, color="#555", ls="-", lw=1.6):
    ax.plot([p[0] for p in pts], [p[1] for p in pts], color=color, ls=ls, lw=lw, solid_capstyle="butt")


def label(x, y, s, color="#444", rot=0, size=9):
    ax.text(x, y, s, ha="center", va="center", fontsize=size, color=color, rotation=rot,
            bbox=dict(fc="white", ec="none", pad=1.2))


ax.text(50, 61.7, "OpenC906 블록 다이어그램  (gen_rtl 디렉터리 기준)", ha="center", fontsize=15)
ax.text(50, 59.7, "※ RVV(벡터 확장)는 오픈 버전에서 비활성 (misa.V = 0)", ha="center", fontsize=9.5, color="#888")

# --- 블록 ---
box(30, 54, 40, 8, "IFU  (ifu/)", "명령 fetch · 분기 예측 BHT / BTB / RAS · I-Cache 32KB", BLUE)
box(30, 42, 40, 7, "IDU  (idu/)", "디코드 · RVC 확장 · WBT scoreboard · dispatch", BLUE)
box(14, 30, 17, 8, "IU  (iu/)", "ALU · BJU\nMUL · DIV", BLUE)
box(35, 30, 22, 8, "FPU  (vf*/)", "VIDU · VDSP (FP 발행)\nVFALU · VFMAU · VFDSU", BLUE)
box(58, 30, 22, 8, "LSU  (lsu/)", "AG → DC · STB\nD-Cache 32KB", BLUE)
box(35, 16, 48, 8, "RTU  (rtu/)", "in-order retire · write-back · 예외 · flush · redirect", BLUE)
box(72, 16, 20, 8, "CP0  (cp0/)", "CSR · 특권 모드\nLPMD (WFI)", BLUE)
box(64, 4, 17, 6.5, "CLINT  (clint/)", "mtime · MSIP", GREEN)
box(84, 4, 17, 6.5, "PLIC  (plic/)", "외부 인터럽트", GREEN)
box(90, 50, 17, 12, "MMU  (mmu/)", "uTLB · JTLB\nPTW (Sv39)", AMBER)
box(90, 36, 17, 6.5, "PMP  (pmp/)", "권한 검사", AMBER)
box(90, 26, 17, 8, "BIU  (biu/)", "AXI4 128bit master\nI-Cache / D-Cache refill", AMBER)
box(14, 4, 26, 7, "PMU (pmu/) · DTU (dtu/)", "성능 카운터 · 디버그 트리거 (연결 생략)", ("#f3f3f3", "#888888"), dashed=True)

# --- 명령 흐름 ---
arrow((30, 50), (30, 45.5)); label(33.5, 47.7, "IBUF")
arrow((14, 38.5), (14, 34)); arrow((35, 38.5), (35, 34)); arrow((50, 38.5), (55, 34))
label(25, 36.3, "dispatch")
arrow((14, 26), (14, 20)); arrow((35, 26), (35, 20)); arrow((58, 26), (57, 20))
arrow((59, 16), (62, 16), both=True); label(63, 22.2, "trap / CSR", size=8)

# --- redirect (왼쪽 레인 2개) ---
line([(11, 16), (1.5, 16), (1.5, 54)], color=RED, ls="--", lw=1.8)
arrow((1.5, 54), (10, 54), color=RED, ls="--", lw=1.8)
label(1.5, 38, "trap / mret / fence.i  redirect", color=RED, rot=90)
line([(6.5, 34), (6.5, 52)], color=RED, ls="--", lw=1.8)
arrow((6.5, 52), (10, 52), color=RED, ls="--", lw=1.8)
label(8.3, 43.5, "BJU mispredict", color=RED, rot=90, size=8)

# --- 주소 변환 / 버스 ---
arrow((50, 54), (81.5, 54), ls=":"); label(66, 56, "VA → PA  (I-uTLB)", size=8.5)
line([(69, 32), (75, 32), (75, 46)], ls=":"); arrow((75, 46), (81.5, 46), ls=":")
label(75, 39, "VA → PA\n(D-uTLB)", size=8)
arrow((90, 44), (90, 39.3)); arrow((90, 32.7), (90, 30))
arrow((69, 28), (81.5, 28), ls=":", both=True); label(75.3, 25.7, "miss / wb", size=8.5)

# --- 인터럽트 ---
arrow((66, 7.4), (68, 12), color=GREEN[1], lw=2); label(58, 9.6, "MTIP / MSIP", color=GREEN[1])
arrow((82, 7.4), (78, 12), color=GREEN[1], lw=2); label(87, 9.6, "MEIP / SEIP", color=GREEN[1])

out = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "f00_core_blocks.png")
fig.savefig(out, dpi=150, bbox_inches="tight", facecolor="white")
print(out)
