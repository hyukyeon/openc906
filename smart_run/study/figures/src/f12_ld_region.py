"""f12_ld_region.png : 영역별 scalar load 의 지연 분해 (p8_bus02_ld_region 실측, 파형에서 단계별 사이클을 셈).

가로 = load 가 DC(EX2) 단계에 있던 사이클을 0 으로 둔 상대 사이클, 끝 = 데이터가 파이프라인으로 돌아온 사이클.
axi_fifo 대기는 0x0~0x1FFFF 의 C=1 읽기에서만 1 cycle 로 고정이고, 그 밖은 0~200 cycle 가변이다.
그림은 그 대기를 1 로 그리고 빗금 + 주석으로 표시한다.
"""
from _draw import canvas, box, save, MONO
from matplotlib.patches import Rectangle

CORE = ("#dbe6f6", "#4a6fa5")   # LSU/BIU 안 (DC -> AR, 또는 DC -> apbif psel)
FIFO = ("#fff1d6", "#c08a2a")   # axi_fifo (SoC 지연 모델)
PATH = ("#efe6f8", "#7a5aa6")   # interconnect / bridge / slave
CAPB = ("#dff0df", "#4a8f4a")   # CPU 내부 APB
RET  = ("#eeeeee", "#888888")   # R(첫 beat) -> 파이프라인 데이터
ERR  = "#c0504d"

# (이름, 부제, [(길이, 색, 글자)], 끝 표시)  끝 표시: None / "fault"
ROWS = [
    ("D-Cache hit", "모든 C=1 영역", [], "hit"),
    ("SRAM · 캐시 miss", "line fill WRAP 4 beat", [(6, CORE, "LFB→AR"), (1, FIFO, "F"), (2, PATH, "SRAM"), (2, RET, "")], None),
    ("SRAM · DE=0", "16B 단일 읽기", [(4, CORE, "AR"), (1, FIFO, "F"), (2, PATH, "SRAM"), (2, RET, "")], None),
    ("미매핑 ERR1/ERR2", "OKAY, 읽기 0", [(6, CORE, "LFB→AR"), (1, FIFO, "F"), (2, PATH, "err"), (2, RET, "")], None),
    ("AHB RAM · DE=0", "axi2ahb → mem_ctrl", [(4, CORE, "AR"), (1, FIFO, "F"), (4, PATH, "AHB"), (2, RET, "")], None),
    ("AHB RAM · 캐시 miss", "AHB burst", [(6, CORE, "LFB→AR"), (1, FIFO, "F"), (7, PATH, "AHB burst"), (2, RET, "")], None),
    ("SoC APB · DE=0", "AXI→AHB→APB", [(4, CORE, "AR"), (1, FIFO, "F"), (5, PATH, "AHB+APB"), (2, RET, "")], None),
    ("SoC APB · 캐시 miss", "주변장치를 line fill", [(6, CORE, "LFB→AR"), (1, FIFO, "F"), (11, PATH, "AHB+APB ×4"), (2, RET, "")], None),
    ("AHB 기본 슬레이브", "hresp ERROR → rresp 2", [(4, CORE, "AR"), (1, FIFO, "F"), (5, PATH, "AHB"), (2, RET, "")], "fault"),
    ("CLINT", "CPU 내부 APB", [(5, CORE, "apbif"), (5, CAPB, "APB")], None),
    ("PLIC", "CPU 내부 APB + 1→x matrix", [(5, CORE, "apbif"), (13, CAPB, "APB + matrix flop")], None),
    ("CPU APB 창의 빈 곳", "sel_none → perr", [(6, CORE, "apbif"), (3, CAPB, "")], "fault"),
]
X0, CW = 30, 3.0         # 0 사이클의 x, 사이클당 폭
RH, Y0 = 5.6, 88


def main():
    fig, ax = canvas(15, 9.2, 100, 100)
    ax.text(50, 97.5, "scalar load 한 번: DC 단계(0)부터 데이터가 돌아올 때까지 (p8_bus02_ld_region 파형 실측)",
            ha="center", va="center", fontsize=12.5, fontweight="bold", color="#222")
    for c in range(0, 22, 2):
        x = X0 + c * CW
        ax.plot([x, x], [Y0 - len(ROWS) * RH + 0.5, Y0 + 1.2], color="#e6e6e6", lw=0.7, zorder=0)
        ax.text(x, Y0 + 2.4, f"+{c}", ha="center", va="center", fontsize=8.5, color="#666")
    for i, (name, sub, segs, end) in enumerate(ROWS):
        y = Y0 - i * RH
        ax.text(1, y - RH / 2 + 0.9, name, ha="left", va="center", fontsize=10.5, fontweight="bold", color="#222")
        ax.text(1, y - RH / 2 - 1.4, sub, ha="left", va="center", fontsize=8, color="#666")
        x = X0
        if end == "hit":
            ax.plot([X0], [y - RH / 2], marker="o", ms=9, color="#4a8f4a")
            ax.text(X0 + 1.5, y - RH / 2, "DC 단계에서 바로 데이터 (load → 사용 2 cycle, 위 TIC/TOC 기준 7 - 5)",
                    ha="left", va="center", fontsize=8.8, color="#333")
            continue
        for ln, col, t in segs:
            w = ln * CW
            box(ax, x, y - RH + 1.0, w, RH - 2.0, col, lw=1.1, r=0.4)
            if col is FIFO:
                ax.add_patch(Rectangle((x, y - RH + 1.0), w, RH - 2.0, fc="none", ec=col[1], hatch="////", lw=0))
            elif t:
                ax.text(x + w / 2, y - RH / 2, t, ha="center", va="center", fontsize=8.2, color="#222")
            x += w
        tot = sum(s[0] for s in segs)
        if end == "fault":
            ax.text(x + 0.8, y - RH / 2, f"+{tot}  → 3 cycle 뒤 load access fault (mcause 5, imprecise)",
                    ha="left", va="center", fontsize=8.8, color=ERR, fontweight="bold")
        else:
            fifo = any(s[1] is FIFO for s in segs)
            note = f"+{tot}" + ("  (+ axi_fifo 대기)" if fifo else "  (고정)")
            ax.text(x + 0.8, y - RH / 2, note, ha="left", va="center", fontsize=8.8, color="#333")
    # 범례
    yb = Y0 - len(ROWS) * RH - 2.5
    lx = 2
    for col, t in [(CORE, "LSU/BIU 안"), (FIFO, "axi_fifo 대기 (그림은 1)"), (PATH, "SoC 버스·슬레이브"),
                   (CAPB, "CPU 내부 APB"), (RET, "첫 beat → 파이프라인")]:
        box(ax, lx, yb - 1.2, 3.0, 2.4, col, lw=1.0, r=0.3)
        if col is FIFO:
            ax.add_patch(Rectangle((lx, yb - 1.2), 3.0, 2.4, fc="none", ec=col[1], hatch="////", lw=0))
        ax.text(lx + 3.8, yb, t, ha="left", va="center", fontsize=9, color="#333")
        lx += 19.5
    ax.text(50, yb - 4.2, "axi_fifo 대기 = 0x0~0x1FFFF 이고 arcache[2]=1(sysmap C=1, DE 와 무관) 이면 1 cycle,  "
            "그 밖은 free-running 카운터 위상에 따라 0~200 cycle (이번 실행 31~195)",
            ha="center", va="center", fontsize=9, color="#a0661a")
    save(fig, "f12_ld_region.png")


if __name__ == "__main__":
    main()
