"""f82_axi.png : C906 BIU 의 AXI4 5 채널과 실제 사용 방식 (Phase 8 §2.1).
   근거: biu/rtl/aq_biu_req_arbiter.v (arlen/awlen 2bit), ifu/rtl/aq_ifu_icache.v:1363-1365,
         lsu/rtl/aq_lsu_lfb.v:913-918, lsu/rtl/aq_lsu_stb.v:1230, lsu/rtl/aq_lsu_vb.v:469"""
from _draw import *

fig, ax = canvas(14, 7.6)
ax.text(50, 97, "C906 BIU 의 AXI4 채널  (master = BIU, slave = SoC)", ha="center", fontsize=15, fontweight="bold")

tbox(ax, 12, 50, 18, 70, "BIU", "AXI4 master\n128bit 데이터\n40bit 주소\n\n요청을 내는 곳\nI-Cache refill\nD-Cache refill (LFB)\nstore (STB)\nwrite-back (VB)", AMBER, ts=13, ss=9.5)
tbox(ax, 88, 50, 18, 70, "SoC", "axi_fifo\n→ interconnect\n→ SRAM · APB …", GRAY, ts=13, ss=9.5)

CH = [
 (77, "AR", "읽기 주소", "araddr · arlen · arburst · arid", "→"),
 (64, "R",  "읽기 데이터", "rdata 128bit · rresp · rlast", "←"),
 (47, "AW", "쓰기 주소", "awaddr · awlen · awburst · awid", "→"),
 (34, "W",  "쓰기 데이터", "wdata 128bit · wstrb 16bit · wlast", "→"),
 (21, "B",  "쓰기 응답", "bresp · bid", "←"),
]
for y, n, ko, sig, d in CH:
    p, q = ((21.5, y), (78.5, y)) if d == "→" else ((78.5, y), (21.5, y))
    arrow(ax, p, q, lw=2.2, ms=16, color="#4a6fa5" if n in ("AR", "R") else "#c08a2a")
    label(ax, 50, y + 3.2, f"{n}  ·  {ko}", size=11.5, bold=True)
    label(ax, 50, y - 3.0, sig, size=9, color="#555")
line(ax, [(23, 56), (77, 56)], color="#bbb", ls=":", lw=1)
ax.text(50, 56.0, "", fontsize=8)

ax.text(2, 4.5,
        "실제 사용: 캐시 refill = WRAP 버스트 4 beat (arlen=3, 64B 라인을 critical-word-first 로)  ·  그 밖의 읽기 = INCR 1 beat\n"
        "쓰기(STB · VB) = INCR.  arlen/awlen 이 2bit 라 한 버스트는 최대 4 beat = 64B.  읽기와 쓰기 채널이 따로라 동시에 진행할 수 있다.",
        fontsize=9.3, color="#333", linespacing=1.55)

save(fig, "f82_axi.png")
