#!/usr/bin/env python3
"""out/*/console.log 의 '@@ key = value' 를 모아 Markdown 표로 출력한다."""
import glob
import os
import re
import sys

root = sys.argv[1] if len(sys.argv) > 1 else "out"
print("# Unit test results\n")
for d in sorted(glob.glob(os.path.join(root, "*"))):
    log = os.path.join(d, "console.log")
    if not os.path.isfile(log):
        continue
    name = os.path.basename(d)
    rep = os.path.join(d, "run_case.report")
    status = "PASS" if os.path.isfile(rep) and "TEST PASS" in open(rep).read() else "FAIL"
    print(f"## {name}  [{status}]\n")
    print("| key | value |\n|---|---:|")
    for line in open(log, errors="replace"):
        m = re.match(r"^@@\s*(\S+)\s*=\s*(\S+)", line)
        if m:
            print(f"| {m.group(1)} | {m.group(2)} |")
    print()
