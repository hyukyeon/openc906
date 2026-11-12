"""f80_soc.png : 테스트벤치 SoC (smart_run/logical/common/soc.v) 블록 다이어그램 (Phase 8 §1.1).
   근거: soc.v 인스턴스, axi/axi_interconnect128.v (SRAM/ERR/APB 범위), ahb/ahb.v (S1/S2), apb/apb.v + apb_bridge.v"""
from _draw import *

fig, ax = canvas(15, 10.5)
ax.text(50, 98.5, "테스트벤치 SoC 구조  (smart_run/logical/common/soc.v)", ha="center", fontsize=15, fontweight="bold")

# --- CPU 서브시스템 / 테스트벤치 ---
tbox(ax, 12, 52, 20, 36, "cpu_sub_system_axi",
     "openC906\n코어 · BIU · CLINT · PLIC\n디버그(tdt)\n\n내부 구조는 1.2절 그림", BLUE, ts=12, ss=9.5)
tbox(ax, 12, 88, 20, 10, "tb.v (테스트벤치)", "SRAM 에 inst/data.pat 적재\nUART write · wb magic 값 감시",
     GRAY, ts=10.5, ss=8.5, ls="--")

# --- AXI ---
tbox(ax, 32, 56, 12, 9, "axi_fifo", "AR 지연 모델", AMBER, ts=11, ss=9)
tbox(ax, 50, 56, 13, 16, "axi_interconnect128", "주소 디코드\n(slave 4 개)", AMBER, ts=10.5, ss=9)
tbox(ax, 72, 82, 19, 10, "axi_slave128", "SRAM 8MB × 2\n0x0000_0000 ~ 0x00FF_FFFF", AMBER, ts=11, ss=9)
tbox(ax, 72, 66, 19, 9, "axi_err128 × 2", "미매핑 ERR1 · ERR2\nOKAY 응답 · 읽기 0 · 쓰기 무시", GRAY, ts=11, ss=9)
tbox(ax, 72, 51, 19, 9, "axi2ahb", "0x1000_0000 ~ 0x1FFF_FFFF", AMBER, ts=11, ss=9)
tbox(ax, 72, 36, 19, 9, "ahb", "AHB 디코드 (128bit)", AMBER, ts=11, ss=9)
tbox(ax, 92, 44, 15, 8.5, "mem_ctrl", "AHB RAM · S1\n0x1F00_0000~0x1F01_FFFF", GRAY, ts=10.5, ss=8)
tbox(ax, 92, 29, 15, 7.5, "err_gen", "AHB 기본 슬레이브\n→ ERROR 응답", GRAY, ts=10.5, ss=8)
tbox(ax, 72, 21, 19, 8, "apb", "ahb2apb → apb_bridge  (S2)", PURP, ts=11, ss=8.5)

# APB 슬레이브 줄
SL = [("intc", "PS4 · 0x1001_0000"), ("timer", "PS2 · 0x1001_1000"), ("UART", "PS1 · 0x1001_5000"),
      ("clkgen", "PS6 · 0x1001_7000"), ("stimer", "PS7 · 0x1001_8000"), ("GPIO", "PS5 · 0x1001_9000"),
      ("bus_delay", "PS8 · 0x1001_A000")]
x0, w, g = 22.5, 10.2, 0.6
xs = [x0 + i * (w + g) + w / 2 for i in range(len(SL))]
for (n, a), cx in zip(SL, xs):
    tbox(ax, cx, 6.5, w, 7.5, n, a, PURP, ts=10.5, ss=7.6)
line(ax, [(72, 17), (72, 13.3)]); line(ax, [(xs[0], 13.3), (xs[-1], 13.3)])
for cx in xs:
    arrow(ax, (cx, 13.3), (cx, 10.25), ms=9, lw=1.2)

# --- 버스 연결 ---
arrow(ax, (22, 56), (26, 56)); label(ax, 24, 59.3, "AXI4\n128bit", size=8.5)
arrow(ax, (38, 56), (43.5, 56)); label(ax, 40.8, 58.6, "AR 지연", size=8)
arrow(ax, (56.5, 62), (62.5, 82)); label(ax, 58.5, 76, "SRAM", size=8.5)
arrow(ax, (56.5, 59), (62.5, 66), ls="--")
arrow(ax, (56.5, 53), (62.5, 51)); label(ax, 59.4, 49.6, "APB 창", size=8.5)
arrow(ax, (72, 46.5), (72, 40.5))
arrow(ax, (81.5, 38), (84.5, 43)); label(ax, 83.4, 39.3, "S1", size=8.5)
arrow(ax, (81.5, 34), (84.5, 30), ls="--")
arrow(ax, (72, 31.5), (72, 25)); label(ax, 74.5, 28.3, "S2", size=8.5)

# tb → SRAM (계층 참조로 적재)
arrow(ax, (22, 88), (62.5, 85), ls=":", color="#888", rad=-0.05)
label(ax, 42, 89, "pat 파일 적재 (계층 참조)", size=8.5, color="#777")

# --- 인터럽트 귀환 ---
line(ax, [(xs[0] - w / 2, 6.5), (6, 6.5), (6, 34)], color=GREEN[1], ls="--", lw=1.8)
arrow(ax, (6, 34), (6, 34.01), color=GREEN[1])
label(ax, 13.3, 21, "주변장치 인터럽트\nxx_intc_vld[39:0]\n→ PLIC 소스 ID 16 + n", color=GREEN[1], size=8.8)

# 범례
ly = 96.0 - 3.2
for i, (c, t) in enumerate([(BLUE, "CPU"), (AMBER, "AXI · AHB · 메모리"), (PURP, "APB 주변장치"), (GRAY, "에러 · 보조")]):
    x = 30 + i * 16.5
    box(ax, x, ly - 0.9, 2.8, 1.8, c, r=0.3)
    ax.text(x + 3.6, ly, t, va="center", fontsize=9)

save(fig, "f80_soc.png")
