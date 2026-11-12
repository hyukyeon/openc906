"""f81_subsystem.png : CPU 서브시스템 뷰 (cpu_sub_system_axi → tr_axi_interconnect → openC906 → aq_top) (Phase 8 §1.2).
   근거: logical/common/cpu_sub_system_axi.v, tr_axi_interconnect.v (wid_entry, rvba, apb_base, xx_intc_int),
         gen_rtl/cpu/rtl/openC906.v, aq_top.v, aq_sysio_top.v, aq_cpuio_top.v, biu/rtl/aq_biu_apbif.v"""
from _draw import *

fig, ax = canvas(15, 11)
ax.text(50, 99.0, "CPU 서브시스템 뷰  (cpu_sub_system_axi 안쪽)", ha="center", fontsize=15, fontweight="bold")

# 바깥 껍질 3 겹
box(ax, 1, 1, 98, 94, ("#fbfbfb", "#999999"), ls="--", r=1.2)
ax.text(2.5, 93.2, "cpu_sub_system_axi  (SoC 쪽 포트 묶음)", fontsize=11, fontweight="bold", color="#555")
box(ax, 3, 3, 94, 87.5, ("#f7f7f7", "#999999"), ls="--", r=1.2)
ax.text(4.5, 88.6, "x_c906_wrapper = tr_axi_interconnect  (SoC 용 설정 · 배선)", fontsize=11, fontweight="bold", color="#555")
box(ax, 5, 5, 70, 80, ("#ffffff", "#4a6fa5"), lw=1.8, r=1.2)
ax.text(6.5, 83.2, "x_cpu_top = openC906  (C906 IP 최상위)", fontsize=11.5, fontweight="bold", color="#2d4f7f")

# aq_top
box(ax, 7, 36, 41, 44, ("#eef3fb", "#4a6fa5"), r=1.0)
ax.text(8.5, 78, "x_aq_top_0 = aq_top  (코어 1 개)", fontsize=10.5, fontweight="bold", color="#2d4f7f")
tbox(ax, 27.5, 66, 38, 13, "aq_core", "IFU · IDU · IU · LSU · FPU · RTU · CP0\n(Phase 1 블록 다이어그램)", BLUE, ts=12, ss=9.2)
tbox(ax, 15, 49.5, 14, 8, "aq_mmu_top", "Sv39 · TLB · PTW", BLUE, ts=10, ss=8.3)
tbox(ax, 29.5, 49.5, 12, 8, "aq_pmp_top", "PMP 8 entry", BLUE, ts=10, ss=8.3)
tbox(ax, 42, 49.5, 9.5, 8, "aq_hpcp", "PMU", BLUE, ts=10, ss=8.3)
tbox(ax, 15, 40.5, 14, 6.5, "aq_dtu_top", "디버그 trigger", BLUE, ts=10, ss=8)
tbox(ax, 35.5, 40.5, 23, 6.5, "aq_cpuio_top", "인터럽트 · time · hartid → CP0", BLUE, ts=10, ss=8)

# openC906 의 나머지 블록
tbox(ax, 61.5, 70, 22, 15, "aq_biu_top", "AXI4 128bit master\n+ apbif (CPU 내부 APB)\naddr[39:27] = apb_base → apbif", AMBER, ts=11, ss=8.6)
tbox(ax, 55.5, 47, 10, 9, "clint_top", "0x40_0400_0000", GREEN, ts=10.5, ss=7.8)
tbox(ax, 67.5, 47, 10, 9, "plic_top", "0x40_0000_0000", GREEN, ts=10.5, ss=7.8)
tbox(ax, 61.5, 29, 22, 10, "aq_sysio_top", "apb_base · rvba 래치 · mtime 카운터\n인터럽트 동기화 · hartid", GREEN, ts=10.5, ss=8.2)
tbox(ax, 17, 15, 20, 12, "tdt_top", "JTAG DTM\n+ Debug Module (Phase 7)", GRAY, ts=10.5, ss=8.5)
tbox(ax, 42, 15, 22, 12, "aq_mp_clk_top\naq_mp_rst_top", "", GRAY, ts=10, ss=8.5)
ax.text(42, 10.5, "클럭 게이팅 · 리셋 동기화", ha="center", fontsize=8.5, color="#333")

# wrapper 가 하는 일
tbox(ax, 86, 70, 18, 15, "wid_entry × 32", "AWID 를 기억해 W 채널에\nWID 를 붙인다\n(AXI3 식 WID, 추정)", AMBER, ts=10.5, ss=8.4)
tbox(ax, 86, 22, 18, 15, "SoC 설정 값", "pad_cpu_rvba = 0x0\n(리셋 PC)\npad_cpu_apb_base\n= 0x40_0000_0000", GRAY, ts=10.5, ss=8.4)
tbox(ax, 86, 47, 18, 18, "인터럽트 배선", "xx_intc_int[39:0]\n→ pad_plic_int_vld[39:0]\nPLIC ID = 16 + n\n(study: [20:19] = TB IRQ\n→ ID 35 · 36)", GREEN, ts=10.5, ss=8.3)

# --- 연결 ---
arrow(ax, (46.5, 70), (50.5, 70), both=True); label(ax, 48.5, 74.0, "캐시\nrefill · wb", size=7.8)
arrow(ax, (72.5, 72), (77, 72)); arrow(ax, (95, 72), (99.8, 72)); label(ax, 97.5, 75, "AXI\n→ SoC", size=8)
arrow(ax, (58, 62.5), (55.5, 51.5), color=GREEN[1]); arrow(ax, (65, 62.5), (67.5, 51.5), color=GREEN[1])
label(ax, 61.5, 58.2, "APB", size=8.5, color=GREEN[1])
arrow(ax, (55.5, 42.5), (58, 34), color=GREEN[1]); arrow(ax, (67.5, 42.5), (65, 34), color=GREEN[1])
label(ax, 53.6, 38.0, "MTIP\nMSIP", size=7.8, color=GREEN[1]); label(ax, 70.8, 38.0, "MEIP\nSEIP", size=7.8, color=GREEN[1])
arrow(ax, (50.5, 29), (47, 40.5), color=GREEN[1]); label(ax, 47.2, 33.0, "동기화된\n인터럽트", size=7.8, color=GREEN[1])
arrow(ax, (77, 47), (72.5, 47), color=GREEN[1], lw=2); label(ax, 74.8, 50.2, "외부 IRQ", size=8, color=GREEN[1])
arrow(ax, (17, 21), (15, 37.2), color="#777", ls="--"); label(ax, 12.6, 29.0, "halt ·\nresume", size=7.8, color="#666")
arrow(ax, (77, 24), (72.5, 27.5), ls=":", color="#777"); label(ax, 74.8, 21.2, "rvba ·\napb_base", size=7.6, color="#666")

save(fig, "f81_subsystem.png")
