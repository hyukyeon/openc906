#!/usr/bin/env python3
"""테스트 소스의 '# GTKW:' 헤더를 읽어 GTKWave 세이브 파일(.gtkw)을 만든다.

사용: mk_gtkw.py <test.S> <vcd path> <out.gtkw> [probe scope]
  probe scope : Verilator = TOP.sim_top.study_probe (기본), iverilog = study_probe
  테스트 헤더 예)  # GTKW: fe bht id ex rt
  'core' 그룹(clk/cycle/mark)은 항상 맨 위에 들어간다.
"""
import os
import re
import sys

# (signal, width, format)   format: b=binary h=hex d=decimal a=ascii
S = sys.argv[4] if len(sys.argv) > 4 else "TOP.sim_top.study_probe"
GROUPS = {
    "core": ("Clock / Mark", [
        ("clk", 1, "b"), ("cycle", 32, "d"), ("mark", 64, "d")]),
    "fe": ("Front-End: IF -> IP -> IBUF", [
        ("fe_if_grant", 1, "b"), ("fe_if_pc", 40, "h"), ("asm_if", 320, "a"),
        ("fe_btb_hit", 1, "b"), ("fe_btb_redirect", 1, "b"),
        ("fe_ip_vld0", 1, "b"), ("fe_ip_vld1", 1, "b"), ("fe_ip_pc", 40, "h"), ("asm_ip", 320, "a"),
        ("fe_ip_br_taken", 1, "b"), ("fe_ip_redirect", 1, "b"), ("fe_ip_redir_pc", 40, "h"),
        ("fe_ip_curflw", 1, "b"), ("fe_ibuf_num", 3, "d"),
        ("fe_ic_access", 1, "b"), ("fe_ic_miss", 1, "b")]),
    "bht": ("Branch predictor: BHT(GHR) / BTB", [
        ("fe_bht_pred", 2, "b"), ("fe_bht_vghr", 14, "b"), ("fe_bht_ghr", 14, "b"),
        ("fe_btb_upd", 1, "b"), ("fe_btb_mispred", 1, "b"),
        ("bju_br_vld", 1, "b"), ("bju_br_taken", 1, "b"), ("bju_bht_mispred", 1, "b")]),
    "ras": ("Return Address Stack / JALR", [
        ("fe_ras_push", 1, "b"), ("fe_ras_pop", 1, "b"), ("fe_ras_ptr", 4, "b"),
        ("fe_ras_ptr_bju", 4, "b"), ("fe_ras_stall", 1, "b"),
        ("bju_ras_mispred", 1, "b"), ("bju_jalr_mispred", 1, "b")]),
    "id": ("Decode / Dispatch (ID)", [
        ("id_vld", 1, "b"), ("id_inst", 32, "h"), ("id_pipedown", 1, "b"), ("id_stall", 1, "b"),
        ("id_stall_raw", 1, "b"), ("id_stall_waw", 1, "b"), ("id_stall_ex1", 1, "b"),
        ("id_stall_cp0", 1, "b"), ("id_stall_split", 1, "b"), ("id_stall_flush", 1, "b")]),
    "ex": ("Execute (EX1..) / Redirect / Forward", [
        ("ex1_vld", 1, "b"), ("ex1_pc", 40, "h"), ("asm_ex1", 320, "a"),
        ("ex1_alu", 1, "b"), ("ex1_bju", 1, "b"), ("ex1_mul", 1, "b"), ("ex1_div", 1, "b"),
        ("ex1_lsu", 1, "b"), ("ex1_cp0", 1, "b"),
        ("iu_redirect", 1, "b"), ("iu_redirect_pc", 40, "h"),
        ("mul_wb", 1, "b"), ("mul_full", 1, "b"), ("div_busy", 1, "b"), ("div_wb", 1, "b"),
        ("fwd0_vld", 1, "b"), ("fwd0_reg", 6, "d"), ("fwd1_vld", 1, "b"), ("fwd1_reg", 6, "d"),
        ("fwd2_vld", 1, "b"), ("fwd2_reg", 6, "d")]),
    "lsu": ("LSU: AG(EX1) -> DC(EX2)", [
        ("lsu_ag_vld", 1, "b"), ("lsu_ag_va", 40, "h"), ("lsu_dc_vld", 1, "b"), ("lsu_dc_pa", 40, "h"),
        ("lsu_dc_ld", 1, "b"), ("lsu_dc_st", 1, "b"), ("lsu_dc_hit", 1, "b"), ("lsu_dc_miss", 1, "b"),
        ("lsu_stb_fwd", 1, "b"), ("lsu_stb_part", 1, "b"), ("lsu_ld_data_vld", 1, "b"), ("lsu_full", 1, "b")]),
    "rt": ("Retire / Write-back / Flush", [
        ("rt_vld", 1, "b"), ("rt_pc", 40, "h"), ("asm_rt", 320, "a"),
        ("wb0_vld", 1, "b"), ("wb0_reg", 6, "d"), ("wb0_data", 64, "h"),
        ("wb1_vld", 1, "b"), ("wb1_reg", 6, "d"), ("wb1_data", 64, "h"),
        ("rt_flush", 1, "b"), ("rt_redirect", 1, "b"), ("rt_redirect_pc", 40, "h"), ("rt_expt", 1, "b")]),
    "cp0": ("CP0: privilege / trap CSR", [
        ("cp0_priv", 2, "b"), ("cp0_mstatus_mie", 1, "b"), ("cp0_mstatus_mpie", 1, "b"),
        ("cp0_mstatus_mpp", 2, "b"), ("cp0_mcause_int", 1, "b"), ("cp0_mcause_code", 5, "d"),
        ("cp0_mepc", 64, "h"), ("cp0_mtval", 64, "h"),
        ("cp0_scause_int", 1, "b"), ("cp0_scause_code", 5, "d"), ("cp0_sepc", 64, "h"), ("cp0_spp", 1, "b")]),
    "irq": ("Interrupt path: source -> PLIC/CLINT -> mip -> retire -> tvec", [
        ("irq_ext0", 1, "b"), ("irq_ext1", 1, "b"), ("irq_age", 16, "d"),
        ("plic_ip35", 1, "b"), ("plic_act35", 1, "b"), ("plic_mclaim", 10, "d"), ("plic_sclaim", 10, "d"),
        ("plic_meip", 1, "b"), ("plic_seip", 1, "b"), ("clint_msip", 1, "b"), ("clint_ssip", 1, "b"),
        ("mip_meip", 1, "b"), ("mip_seip", 1, "b"), ("mip_msip", 1, "b"), ("mip_ssip", 1, "b"),
        ("mie_meie", 1, "b"), ("mie_seie", 1, "b"), ("mie_msie", 1, "b"), ("mie_ssie", 1, "b"),
        ("int_req", 1, "b"), ("int_vec", 5, "d"),
        ("fe_if_pc", 40, "h"), ("asm_rt", 320, "a"), ("rt_pc", 40, "h"),
        ("rt_expt", 1, "b"), ("rt_redirect", 1, "b"), ("rt_redirect_pc", 40, "h")]),
    "trap": ("Trap CSRs: M (mtvec/mepc/mcause/mstatus) vs S (stvec/sepc/scause/sstatus)", [
        ("cp0_priv", 2, "b"),
        ("cp0_mtvec", 64, "h"), ("cp0_mepc", 64, "h"), ("cp0_mcause_int", 1, "b"), ("cp0_mcause_code", 5, "d"),
        ("cp0_mstatus_mie", 1, "b"), ("cp0_mstatus_mpie", 1, "b"), ("cp0_mstatus_mpp", 2, "b"),
        ("cp0_stvec", 64, "h"), ("cp0_sepc", 64, "h"), ("cp0_scause_int", 1, "b"), ("cp0_scause_code", 5, "d"),
        ("cp0_sstatus_sie", 1, "b"), ("cp0_sstatus_spie", 1, "b"), ("cp0_spp", 1, "b"),
        ("cp0_mideleg", 64, "h")]),
    "wfi": ("WFI loop: while (!int_flag) { wfi; }", [
        ("int_flag", 32, "d"), ("wfi_state", 2, "d"), ("wfi_in_lpmd", 1, "b"), ("wfi_wake", 1, "b"),
        ("irq_ext0", 1, "b"), ("irq_ext1", 1, "b"), ("plic_mclaim", 10, "d"),
        ("mip_meip", 1, "b"), ("mie_meie", 1, "b"), ("cp0_mstatus_mie", 1, "b"), ("int_req", 1, "b"),
        ("fe_if_pc", 40, "h"), ("asm_rt", 320, "a"), ("rt_pc", 40, "h"),
        ("rt_expt", 1, "b"), ("rt_redirect_pc", 40, "h"),
        ("cp0_mepc", 64, "h"), ("cp0_mcause_code", 5, "d")]),
    "bus": ("AXI master (BIU)", [
        ("bus_arvalid", 1, "b"), ("bus_arready", 1, "b"), ("bus_araddr", 40, "h"), ("bus_arlen", 8, "d"),
        ("bus_rvalid", 1, "b"), ("bus_rlast", 1, "b"),
        ("bus_awvalid", 1, "b"), ("bus_awaddr", 40, "h"), ("bus_wvalid", 1, "b"), ("bus_bvalid", 1, "b")]),
}
FLAG = {"b": "28", "h": "22", "d": "24", "a": "800"}


def trace_line(name, width):
    return f"{S}.{name}" if width == 1 else f"{S}.{name}[{width - 1}:0]"


def main():
    src, vcd, out = sys.argv[1:4]
    groups = ["core"]
    for line in open(src):
        m = re.match(r"^\s*#\s*GTKW:\s*(.*)$", line)
        if m:
            groups += [g for g in m.group(1).split() if g in GROUPS and g not in groups]
    lines = [
        "[*] generated by tools/mk_gtkw.py",
        f'[dumpfile] "{os.path.abspath(vcd)}"',
        "[timestart] 0",
        "[size] 1800 1000",
        "[pos] -1 -1",
        "[sst_width] 220",
        "[signals_width] 300",
        "[sst_expanded] 1",
        "[sst_vpaned_height] 300",
    ]
    for g in groups:
        title, sigs = GROUPS[g]
        lines += ["@800200", f"-{title}"]
        last = None
        for name, width, fmt in sigs:
            if FLAG[fmt] != last:
                lines.append("@" + FLAG[fmt])
                last = FLAG[fmt]
            lines.append(trace_line(name, width))
        lines += ["@1000200", f"-{title}"]
    lines.append("[pattern_trace] 1")
    lines.append("[pattern_trace] 0")
    open(out, "w").write("\n".join(lines) + "\n")


if __name__ == "__main__":
    main()
