#!/usr/bin/env python3
"""GTKWave 화면을 헤드리스(Xvfb)로 띄워 특정 mark 구간 파형을 PNG 로 저장한다.

사용: wave_snap.py <out/test 디렉토리> --mark N [--from-cycle C0 --to-cycle C1] [--groups fe,ex,rt] -o out.png
  --groups : 표시할 신호 그룹(mk_gtkw.py 의 그룹 이름). 기본은 테스트 헤더의 '# GTKW:' 그룹.
필요: Xvfb, gtkwave, ImageMagick(import, convert)
"""
import argparse
import glob
import os
import subprocess
import sys
import tempfile
import time

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import mk_gtkw  # noqa: E402

SCOPE = "TOP.sim_top.study_probe"
SIG_INFO = {n: (w, f) for _, (_, sigs) in mk_gtkw.GROUPS.items() for (n, w, f) in sigs}


def gtkw_for_signals(names, vcd, width, height):
    """지정한 신호만 담은 gtkw (그룹 없이)"""
    lines = [f'[dumpfile] "{os.path.abspath(vcd)}"', f"[size] {width} {height}", "[pos] -1 -1",
             "[sst_expanded] 0", "[signals_width] 230"]
    for n in names:
        if n.startswith("-"):
            lines += ["@200", n]            # 구분용 빈 줄/제목
            continue
        w, fmt = SIG_INFO[n]
        lines.append("@" + mk_gtkw.FLAG[fmt])
        lines.append(f"{SCOPE}.{n}" if w == 1 else f"{SCOPE}.{n}[{w - 1}:0]")
    return "\n".join(lines) + "\n"


def cycle_times(vcd):
    """study_probe.cycle 값 -> 시간(VCD 단위) 매핑, mark 값 이력"""
    ids = {}
    scope = []
    t = 0
    cyc, marks = {}, []
    with open(vcd) as f:
        for line in f:
            line = line.strip()
            if line.startswith("$scope"):
                scope.append(line.split()[2])
            elif line.startswith("$upscope"):
                scope.pop()
            elif line.startswith("$var"):
                p = line.split()
                if scope and scope[-1] == "study_probe" and p[4] in ("cycle", "mark"):
                    ids[p[3]] = p[4]
            elif line.startswith("#"):
                t = int(line[1:])
            elif line.startswith("b"):
                v, i = line[1:].split()
                if ids.get(i) == "cycle" and "x" not in v:
                    cyc.setdefault(int(v, 2), t)
                elif ids.get(i) == "mark" and "x" not in v:
                    marks.append((t, int(v, 2)))
    return cyc, marks


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("outdir")
    ap.add_argument("--mark", type=int)
    ap.add_argument("--from-cycle", type=int)
    ap.add_argument("--to-cycle", type=int)
    ap.add_argument("--groups")
    ap.add_argument("--signals", help="쉼표로 구분한 study_probe 신호 이름 ('-제목' 은 구분선)")
    ap.add_argument("--pad", type=int, default=3, help="앞뒤 여유 사이클")
    ap.add_argument("--width", type=int, default=1900)
    ap.add_argument("--height", type=int, default=1000)
    ap.add_argument("-o", "--output", required=True)
    a = ap.parse_args()

    test = os.path.basename(os.path.normpath(a.outdir))
    vcd = glob.glob(os.path.join(a.outdir, "*.vcd"))[0]
    stem = test.split("_gshare")[0]
    src = os.path.join(HERE, "..", "tests", stem, stem + ".S")
    cyc, marks = cycle_times(vcd)
    if a.from_cycle is not None:
        t0, t1 = cyc[a.from_cycle], cyc[a.to_cycle]
    else:
        t0 = t1 = None
        for i, (t, m) in enumerate(marks):
            if m == a.mark and t0 is None:
                t0 = t
                t1 = marks[i + 1][0] if i + 1 < len(marks) else t + 10000
        if t0 is None:
            sys.exit(f"mark {a.mark} not found")
    period = 100  # 10ns / 100ps
    t0 = max(0, t0 - a.pad * period)
    t1 = t1 + a.pad * period
    t0_ps, t1_ps = t0 * 100, t1 * 100   # VCD timescale 100ps -> GTKWave 는 ps 로 받는다

    with tempfile.TemporaryDirectory() as td:
        gtkw = os.path.join(td, "v.gtkw")
        if a.signals:
            open(gtkw, "w").write(gtkw_for_signals(a.signals.split(","), vcd, a.width, a.height))
        else:
            groups = a.groups.split(",") if a.groups else None
            if groups:
                hdr = os.path.join(td, "hdr.S")
                open(hdr, "w").write("# GTKW: " + " ".join(groups) + "\n")
                srcf = hdr
            else:
                srcf = src
            mk_gtkw.S = SCOPE
            sys.argv = ["mk_gtkw.py", srcf, vcd, gtkw, SCOPE]
            mk_gtkw.main()
            txt = open(gtkw).read().replace("[size] 1800 1000", f"[size] {a.width} {a.height}")
            txt = txt.replace("[signals_width] 300", "[signals_width] 230").replace("[sst_expanded] 1", "[sst_expanded] 0")
            open(gtkw, "w").write(txt)
        tcl = os.path.join(td, "zoom.tcl")
        open(tcl, "w").write(f"gtkwave::setZoomRangeTimes {t0_ps} {t1_ps}\n")
        disp = ":97"
        xv = subprocess.Popen(["Xvfb", disp, "-screen", "0", f"{a.width + 40}x{a.height + 60}x24"],
                              stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        time.sleep(1.5)
        env = dict(os.environ, DISPLAY=disp)
        gw = subprocess.Popen(["gtkwave", "-a", gtkw, vcd, "--script", tcl],
                              env=env, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        time.sleep(8)
        raw = os.path.join(td, "raw.png")
        subprocess.run(["import", "-display", disp, "-window", "root", raw], check=True)
        gw.terminate()
        xv.terminate()
        subprocess.run(["convert", raw, "-trim", "+repage", a.output], check=True)
    print(a.output)


if __name__ == "__main__":
    main()
