#!/usr/bin/env python3
"""study_probe 의 trace.log 를 사람이 읽는 파이프라인 표로 바꾼다.

사용: pipeview.py <out/test 디렉토리> [--mark N] [--max-rows K]
출력: <dir>/pipeview.txt  (mark 구간별 표 + 구간 요약)

  열 의미
    IF   : 이번 사이클 I-Cache 에 요청을 낸 fetch 주소 (grant 된 경우)
    IP   : I$ 데이터가 돌아와 pre-decode/BHT/RAS 가 보는 단계 (IFU 의 'ID' 단계)
    IB   : IBUF 에 쌓인 명령 수
    ID   : IDU 가 디코드/hazard 검사 중인 명령 ('>' = 이번 사이클 EX1 로 내려감, '.' = stall)
           IDU 에는 PC 가 없으므로 '다음에 EX1 에 들어온 명령의 PC' 로 역추적해서 표시
    EX1  : IU/LSU/CP0 가 실행 중인 명령 (PC 는 IU 가 자체 계산)
    RT   : 이번 사이클 retire 된 명령
"""
import glob
import os
import re
import sys
from collections import Counter, OrderedDict

INSN_RE = re.compile(r"^\s*([0-9a-f]+):\s+([0-9a-f]+)\s+(.*)$")
LABEL_RE = re.compile(r"^([0-9a-f]+) <(.+)>:$")
EU_NAMES = ["ALU", "BJU", "MUL", "DIV", "CP0", "LSU", "b6", "b7", "FP", "VEC"]


def load_objdump(path):
    by_pc, by_enc, labels = {}, {}, {}
    label = None
    for line in open(path):
        line = line.rstrip()
        m = LABEL_RE.match(line)
        if m:
            label = m.group(2)
            continue
        m = INSN_RE.match(line)
        if not m:
            continue
        pc, enc = int(m.group(1), 16), m.group(2)
        text = re.sub(r"\s+", " ", m.group(3).split("#")[0]).strip()
        text = re.sub(r" <[^>]*>", "", text)
        by_pc[pc] = text
        by_enc.setdefault(enc, text)
        if label:
            labels[pc] = label
            label = None
    return by_pc, by_enc, labels


def short(pc, by_pc, width):
    t = by_pc.get(pc, "?")
    s = f"{pc & 0xffff:04x} {t}"
    return s[:width].ljust(width)


def main():
    d = sys.argv[1]
    want_mark = None
    max_rows = 400
    if "--mark" in sys.argv:
        want_mark = int(sys.argv[sys.argv.index("--mark") + 1])
    if "--max-rows" in sys.argv:
        max_rows = int(sys.argv[sys.argv.index("--max-rows") + 1])
    objdump = glob.glob(os.path.join(d, "*.objdump"))[0]
    by_pc, by_enc, labels = load_objdump(objdump)

    rows = []
    with open(os.path.join(d, "trace.log")) as f:
        header = f.readline().lstrip("#").split()
        for line in f:
            v = line.split()
            if len(v) != len(header):
                continue
            rows.append(dict(zip(header, v)))

    # ID 단계 PC 추론: IDU 는 PC 를 들고 있지 않다(IU 가 EX1 PC 를 자체 계산).
    # in-order 이므로 'ID 에서 pipedown 된 명령' = '다음 사이클 EX1 명령' 이다.
    # 뒤에서부터 훑으며 다음 pipedown 의 EX1 PC 를 ID 행에 채운다. (flush 로 사라진 명령은 None)
    nxt = None
    for i in range(len(rows) - 1, -1, -1):
        r = rows[i]
        if r["flush"] == "1" or r["iu_redir"] == "1" or r["rt_redir"] == "1":
            nxt = None
        if r["id_v"] == "1" and r["pipedown"] == "1" and i + 1 < len(rows) and rows[i + 1]["ex1_v"] == "1":
            nxt = int(rows[i + 1]["ex1_pc"], 16)
        r["_id_pc"] = nxt if r["id_v"] == "1" else None
        if r["id_v"] == "1" and r["pipedown"] == "1":
            pass

    sections = OrderedDict()
    for r in rows:
        mk = int(r["mark"])
        if mk >= 1 << 16:          # x31 이 아직 초기화되지 않은 리셋 직후 구간
            continue
        sections.setdefault(mk, []).append(r)

    W = 24
    out = []
    out.append(__doc__.split("\n\n")[1] if "\n\n" in __doc__ else "")
    for mark, rs in sections.items():
        if want_mark is not None and mark != want_mark:
            continue
        st = Counter()
        out.append("")
        out.append("=" * 160)
        out.append(f"MARK {mark}   cycles {rs[0]['cyc']} .. {rs[-1]['cyc']}  ({len(rs)} cycles)")
        out.append("=" * 160)
        out.append(f"{'cyc':>7} | {'IF (fetch)':{W}} | {'IP (pred)':{W}} |IB| {'ID':{W}} | {'EX1':{W}} | {'RETIRE':{W}} | events")
        out.append("-" * 160)
        for i, r in enumerate(rs):
            b = lambda k: r[k] == "1"
            h = lambda k: int(r[k], 16)
            if_c = short(h("if_pc"), by_pc, W) if b("if_g") else " " * W
            ip_c = short(h("ip_pc"), by_pc, W) if b("ip_v0") else " " * W
            if b("id_v"):
                mark_c = ">" if b("pipedown") else "."
                if r["_id_pc"] is not None:
                    id_c = (mark_c + short(r["_id_pc"], by_pc, W - 1))[:W].ljust(W)
                else:
                    enc = r["id_inst"]
                    t = by_enc.get(enc) or by_enc.get(enc[-4:]) or "?"
                    id_c = f"{mark_c}(flushed) {t}"[:W].ljust(W)
            else:
                id_c = " " * W
            if b("ex1_v"):
                eu = int(r["ex1_eu"], 2)
                eu_s = "/".join(n for k, n in enumerate(EU_NAMES) if eu >> k & 1)
                ex_c = short(h("ex1_pc"), by_pc, W - 4)[: W - 4] + f" {eu_s[:3]:3}"
            else:
                ex_c = " " * W
            rt_c = short(h("rt_pc"), by_pc, W) if b("rt_v") else " " * W
            ev = []
            if b("btb_redir"): ev.append("BTB-redirect"); st["btb_redirect"] += 1
            if b("ip_redir"): ev.append(f"IP-redirect->{h('ip_redir_pc') & 0xffff:04x}"); st["ip_redirect"] += 1
            if b("ip_curflw"): ev.append("IP-curflw(RAS/delay)"); st["ip_curflw"] += 1
            if b("stall"):
                why = [n for n, k in (("RAW", "raw"), ("WAW", "waw"), ("EX1-busy", "ex1st"), ("CP0/fence", "cp0st")) if b(k)]
                ev.append("ID-stall:" + (",".join(why) if why else "other"))
                for w in why or ["other"]:
                    st["stall_" + w] += 1
            if b("br_v"): ev.append("BR-resolve:" + ("T" if b("br_taken") else "N"))
            if b("bht_misp"): ev.append("MISPRED(BHT)"); st["mispred_bht"] += 1
            if b("jalr_misp"): ev.append("JALR-redirect"); st["jalr_redirect"] += 1
            if b("ras_misp"): ev.append("MISPRED(RAS)"); st["mispred_ras"] += 1
            if b("iu_redir"): ev.append(f"IU-redirect->{h('iu_redir_pc') & 0xffff:04x}"); st["iu_redirect"] += 1
            if b("mul_wb"): ev.append("MUL-wb")
            if b("div_busy"): st["div_busy_cycles"] += 1
            if b("dc_v"):
                kind = "LD" if b("dc_ld") else ("ST" if b("dc_st") else "LS")
                hm = "hit" if b("dc_hit") else ("MISS" if b("dc_miss") else "")
                ev.append(f"DC:{kind} {hm}".rstrip())
                if b("dc_miss"): st["dc_miss"] += 1
            if b("stb_fwd"): ev.append("STB-fwd"); st["stb_fwd"] += 1
            if r.get("stb_part") == "1": ev.append("STB-partial"); st["stb_partial"] += 1
            if r.get("ic_miss") == "1": ev.append("I$-miss"); st["icache_miss"] += 1
            if b("flush"): ev.append("FLUSH"); st["flush"] += 1
            if b("rt_redir"): ev.append(f"RT-redirect->{h('rt_redir_pc') & 0xffff:04x}")
            if b("expt"): ev.append("TRAP"); st["trap"] += 1
            if b("rt_v"): st["retired"] += 1
            if i < max_rows:
                out.append(f"{r['cyc']:>7} | {if_c} | {ip_c} |{r['ibuf']:>2}| {id_c} | {ex_c} | {rt_c} | {' '.join(ev)}")
            elif i == max_rows:
                out.append(f"   ... ({len(rs) - max_rows} more cycles, use --mark {mark} --max-rows N)")
        n = len(rs)
        out.append("-" * 160)
        summ = ", ".join(f"{k}={v}" for k, v in sorted(st.items()))
        ipc = st["retired"] / n if n else 0
        out.append(f"summary: cycles={n} retired={st['retired']} IPC={ipc:.3f} | {summ}")
    open(os.path.join(d, "pipeview.txt"), "w").write("\n".join(out) + "\n")
    print("\n".join(out))


if __name__ == "__main__":
    main()
