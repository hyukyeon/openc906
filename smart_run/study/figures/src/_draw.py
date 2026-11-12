"""matplotlib 그림 공통 도우미 (f00d, f80~f82). Notion venv(~/06_Notion/venv)의 matplotlib 으로 실행한다."""
import os
import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
from matplotlib import font_manager
from matplotlib.patches import FancyBboxPatch, FancyArrowPatch

for _f in font_manager.findSystemFonts():
    if "wqy-zenhei" in _f.lower():
        font_manager.fontManager.addfont(_f)
plt.rcParams["font.family"] = ["WenQuanYi Zen Hei", "DejaVu Sans"]

BLUE  = ("#eef3fb", "#4a6fa5")   # 코어
AMBER = ("#fff6e5", "#c08a2a")   # 버스 · 메모리 시스템
GREEN = ("#eaf5ea", "#4a8f4a")   # 인터럽트 · CPU 내부 APB
PURP  = ("#f3ecfa", "#7a5aa6")   # SoC 주변장치
GRAY  = ("#f3f3f3", "#888888")   # 미매핑 · 보조
RED   = "#c0504d"
MONO  = "DejaVu Sans Mono"


def canvas(w, h, xmax=100, ymax=100):
    fig, ax = plt.subplots(figsize=(w, h))
    ax.set_xlim(0, xmax); ax.set_ylim(0, ymax); ax.axis("off")
    return fig, ax


def box(ax, x0, y0, w, h, c, lw=1.5, ls="-", r=1.0, alpha=1.0):
    ax.add_patch(FancyBboxPatch((x0, y0), w, h, boxstyle=f"round,pad=0,rounding_size={r}",
                                fc=c[0], ec=c[1], lw=lw, ls=ls, alpha=alpha))


def tbox(ax, cx, cy, w, h, title, sub="", c=BLUE, ts=12, ss=9.5, ls="-", r=1.0):
    """중심 좌표 기준 상자 + 제목 + 부제."""
    box(ax, cx - w / 2, cy - h / 2, w, h, c, ls=ls, r=r)
    if sub:
        ax.text(cx, cy + h * 0.18, title, ha="center", va="center", fontsize=ts, fontweight="bold", color="#222")
        ax.text(cx, cy - h * 0.20, sub, ha="center", va="center", fontsize=ss, color="#333", linespacing=1.35)
    else:
        ax.text(cx, cy, title, ha="center", va="center", fontsize=ts, fontweight="bold", color="#222")


def arrow(ax, p, q, color="#555", ls="-", both=False, lw=1.6, rad=0.0, ms=13):
    ax.add_patch(FancyArrowPatch(p, q, arrowstyle="<|-|>" if both else "-|>", mutation_scale=ms,
                                 color=color, lw=lw, ls=ls, connectionstyle=f"arc3,rad={rad}",
                                 shrinkA=0, shrinkB=0))


def line(ax, pts, color="#555", ls="-", lw=1.6):
    ax.plot([p[0] for p in pts], [p[1] for p in pts], color=color, ls=ls, lw=lw, solid_capstyle="butt")


def label(ax, x, y, s, color="#444", size=9, rot=0, ha="center", bold=False, bg=True):
    ax.text(x, y, s, ha=ha, va="center", fontsize=size, color=color, rotation=rot,
            fontweight="bold" if bold else "normal",
            bbox=dict(fc="white", ec="none", pad=1.0) if bg else None)


def save(fig, name):
    out = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", name)
    fig.savefig(out, dpi=150, bbox_inches="tight", facecolor="white")
    print(os.path.normpath(out))
