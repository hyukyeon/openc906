"""f11_exec_flow.png : 유닛별 실행 흐름 (p3_be06_exec_mix MARK 1~7 의 pipeview 실측).

가로 = EX1 에 들어간 사이클을 0 으로 둔 상대 사이클. 각 행은 명령 하나와 그 바로 뒤의 사용 명령.
  파랑 = EX1 점유, 연파랑 = MUL EX2/EX3, 보라 = DIV 반복 상태, 주황 = LSU DC 단계,
  초록 = 레지스터 파일 쓰기(wb0/wb1), 빨간 삼각형 = retire, 검은 테두리 = 사용 명령이 EX1 에 들어가는 사이클
"""
from _draw import canvas, box, label, save, line, MONO
from matplotlib.patches import Polygon, Rectangle

EX = ("#dbe6f6", "#4a6fa5")
MU = ("#eef3fb", "#7d97c2")
DV = ("#efe6f8", "#7a5aa6")
DC = ("#fff1d6", "#c08a2a")
WB = ("#dff0df", "#4a8f4a")
MISS = ("#fbe9e7", "#c0504d")

# (이름, 부제, [(cycle, text, color)], retire cycle, use cycle)
ROWS = [
    ("add", "ALU", [(0, "EX1", EX), (1, "wb0", WB)], 1, 1),
    ("mul (작은 값)", "MUL 3단", [(0, "EX1", EX), (1, "EX2", MU), (2, "EX3\nfwd1", MU), (3, "wb0", WB)], 1, 3),
    ("mul (64bit 큰 값)", "split 4회", [(0, "EX1", EX), (1, "EX1\nsplit0", EX), (2, "EX1\nsplit1", EX), (3, "EX1\ncmplt", EX),
                                       (4, "EX2", MU), (5, "EX3\nfwd1", MU), (6, "wb0", WB)], 4, 6),
    ("divu 1000/3", "DIV 반복", [(0, "EX1", EX), (1, "준비", DV), (2, "align", DV)] +
     [(c, "iter", DV) for c in range(3, 8)] + [(8, "done", DV), (9, "wb0", WB)], 1, 10),
    ("ld (hit)", "LSU", [(0, "EX1\nAG", EX), (1, "DC\nhit·fwd2", DC), (2, "wb1", WB)], 1, 2),
    ("ld (miss)", "LSU", [(0, "EX1\nAG", EX), (1, "DC\nmiss", MISS), (2, "refill", MISS)], 1, None),
    ("sd", "LSU", [(0, "EX1\nAG", EX), (1, "DC\n→STB", DC)], 1, None),
]
NC = 12                      # 0..11
X0, CW = 22, 6.2             # 첫 열 x, 열 폭
RH, Y0 = 8.2, 74             # 행 높이, 첫 행 y


def main():
    fig, ax = canvas(15, 7.6, 100, 82)
    ax.set_ylim(10, 82)
    ax.text(50, 80.5, "명령 하나의 실행 흐름: EX1 complete → 다음 사이클 retire, 레지스터 쓰기는 유닛마다 다르다",
            ha="center", va="center", fontsize=12.5, fontweight="bold", color="#222")
    for c in range(NC):
        label(ax, X0 + c * CW + CW / 2, Y0 + 3.6, f"+{c}", size=9, color="#555", bg=False)
    for i, (name, sub, cells, rt, use) in enumerate(ROWS):
        y = Y0 - i * RH
        ax.text(1, y - RH / 2 + 1.0, name, ha="left", va="center", fontsize=11, fontweight="bold", color="#222")
        ax.text(1, y - RH / 2 - 2.0, sub, ha="left", va="center", fontsize=8.5, color="#666")
        for c in range(NC):
            ax.add_patch(Rectangle((X0 + c * CW, y - RH + 0.6), CW, RH - 1.2, fc="white", ec="#e4e4e4", lw=0.6))
        for c, t, col in cells:
            w = CW - 0.6
            if t == "refill":
                w = CW * (NC - c) - 0.6
            box(ax, X0 + c * CW + 0.3, y - RH + 1.0, w, RH - 2.0, col, lw=1.2, r=0.6)
            if t == "refill":
                continue
            ax.text(X0 + c * CW + 0.3 + w / 2, y - RH / 2, t, ha="center", va="center", fontsize=8.6,
                    color="#222", linespacing=1.15)
        # retire 표시: 해당 열 위쪽의 빨간 삼각형
        xr = X0 + rt * CW + CW / 2
        ax.add_patch(Polygon([(xr - 1.0, y + 0.1), (xr + 1.0, y + 0.1), (xr, y - 1.5)], closed=True, fc="#c0504d", ec="none"))
        if use is not None:
            xu = X0 + use * CW
            ax.add_patch(Rectangle((xu + 0.15, y - RH + 0.8), CW - 0.3, RH - 1.6, fc="none", ec="#222", lw=2.0, ls="--"))
    yb = Y0 - len(ROWS) * RH - 1.0
    ax.text(X0 + 3 * CW + CW / 2, Y0 - 5 * RH - RH / 2 - 0.2, "", fontsize=8)
    # ld miss 주석
    ax.text(X0 + 8.2 * CW, Y0 - 5 * RH - RH / 2, "refill 대기: 데이터 ≈ +50~60 (그다음 wb1·사용 명령 EX1). 그동안 뒤 명령은 계속 retire", ha="center", va="center",
            fontsize=8.6, color="#a33")
    ax.text(X0 + 7.5 * CW, Y0 - 6 * RH - RH / 2, "retire 뒤 STB → D-Cache (같은 주소 load 는 STB 에서 forward)",
            ha="center", va="center", fontsize=8.6, color="#555")
    # 범례
    lx = 2
    items = [(EX, "EX1 점유"), (MU, "MUL EX2/EX3"), (DV, "DIV 상태"), (DC, "LSU DC(EX2)"), (WB, "레지스터 쓰기"), (MISS, "miss")]
    for col, t in items:
        box(ax, lx, yb - 2.6, 3.0, 2.4, col, lw=1.0, r=0.4)
        ax.text(lx + 3.6, yb - 1.4, t, ha="left", va="center", fontsize=9, color="#333")
        lx += 13.5
    xr = lx + 1.5
    ax.add_patch(Polygon([(xr - 1.0, yb - 0.4), (xr + 1.0, yb - 0.4), (xr, yb - 2.2)], closed=True, fc="#c0504d", ec="none"))
    ax.text(xr + 1.8, yb - 1.4, "retire", ha="left", va="center", fontsize=9, color="#333")
    ax.add_patch(Rectangle((xr + 9, yb - 2.6), 3.0, 2.4, fc="none", ec="#222", lw=1.6, ls="--"))
    ax.text(xr + 12.6, yb - 1.4, "사용 명령 EX1", ha="left", va="center", fontsize=9, color="#333")
    save(fig, "f11_exec_flow.png")


if __name__ == "__main__":
    main()
