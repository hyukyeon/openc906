#!/usr/bin/env python3
"""study_probe VCD 에서 특정 mark 구간의 신호 변화를 텍스트로 뽑는다.

사용 예:
  vcd_query.py out/p4_mem01_dcache/p4_mem01_dcache.vcd --mark 1 \
      --signals bus_arvalid,bus_araddr,bus_arlen,bus_rvalid,bus_rlast
  --cycles  : 변화 시점을 시간 대신 study_probe.cycle 값으로 표시 (기본)
  --max N   : 최대 출력 줄 수
신호 이름은 study_probe 안의 이름(접두어 없이)으로 준다.
"""
import argparse


def parse(path, want):
    ids, widths = {}, {}
    hist = {}
    scope = []
    t = 0
    with open(path) as f:
        for line in f:
            line = line.strip()
            if not line:
                continue
            if line.startswith("$scope"):
                scope.append(line.split()[2])
            elif line.startswith("$upscope"):
                scope.pop()
            elif line.startswith("$var"):
                p = line.split()
                if scope and scope[-1] == "study_probe" and p[4] in want:
                    ids.setdefault(p[3], []).append(p[4])
                    widths[p[4]] = int(p[2])
            elif line.startswith("#"):
                t = int(line[1:])
            elif line[:1] in "01xz" and line[1:].strip() in ids:
                for n in ids[line[1:].strip()]:
                    hist.setdefault(n, []).append((t, line[0]))
            elif line[:1] == "b":
                v, i = line[1:].split()
                if i in ids:
                    for n in ids[i]:
                        hist.setdefault(n, []).append((t, v))
    return hist, widths


def value_at(h, t):
    v = None
    for tt, vv in h:
        if tt > t:
            break
        v = vv
    return v


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("vcd")
    ap.add_argument("--mark", type=int)
    ap.add_argument("--signals", required=True)
    ap.add_argument("--max", type=int, default=200)
    a = ap.parse_args()
    sigs = a.signals.split(",")
    hist, widths = parse(a.vcd, set(sigs) | {"mark", "cycle"})
    # mark 구간 [t0, t1)
    t0, t1 = 0, 1 << 62
    if a.mark is not None:
        on = False
        for t, v in hist["mark"]:
            iv = int(v, 2) if "x" not in v else -1
            if iv == a.mark and not on:
                t0, on = t, True
            elif on and iv != a.mark:
                t1 = t
                break
    ev = []
    for s in sigs:
        for t, v in hist.get(s, []):
            if t0 <= t < t1:
                ev.append((t, s, v))
    ev.sort()
    cyc_h = hist["cycle"]
    n = 0
    for t, s, v in ev:
        c = value_at(cyc_h, t)
        c = int(c, 2) if c and "x" not in c else -1
        if widths.get(s, 1) > 1 and "x" not in v:
            v = hex(int(v, 2))
        print(f"cycle {c:>7}  {s:<18} = {v}")
        n += 1
        if n >= a.max:
            print("...")
            break


if __name__ == "__main__":
    main()
