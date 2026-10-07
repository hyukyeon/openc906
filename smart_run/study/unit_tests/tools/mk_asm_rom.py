#!/usr/bin/env python3
"""objdump -d 결과로 study_probe 의 asm_rom (PC -> 40글자 ASCII) 초기화 파일을 만든다.

사용: mk_asm_rom.py <prog.objdump> <asm_rom.hex>
  - 인덱스 = PC >> 1 (halfword 단위, RVC 대응)
  - 라벨 첫 명령에는 "<label>:" 를 앞에 붙인다.
"""
import re
import sys

WIDTH = 40
INSN_RE = re.compile(r"^\s*([0-9a-f]+):\s+([0-9a-f]+)\s+(.*)$")
LABEL_RE = re.compile(r"^([0-9a-f]+) <(.+)>:$")


def parse_objdump(path):
    """{pc: text} 반환. text 는 '라벨: 명령' 형태."""
    rom, label = {}, None
    for line in open(path):
        line = line.rstrip("\n")
        m = LABEL_RE.match(line)
        if m:
            label = m.group(2)
            continue
        m = INSN_RE.match(line)
        if not m:
            continue
        pc = int(m.group(1), 16)
        text = re.sub(r"\s+", " ", m.group(3).split("#")[0]).strip()
        text = re.sub(r" <[^>]*>", "", text)      # 'j 1c <loop>' -> 'j 1c'
        if label:
            text = f"{label}: {text}"
            label = None
        rom[pc] = text
    return rom


def main():
    rom = parse_objdump(sys.argv[1])
    with open(sys.argv[2], "w") as f:
        for pc in sorted(rom):
            if pc >= 0x8000:
                continue
            s = rom[pc][:WIDTH].ljust(WIDTH)
            f.write(f"@{pc >> 1:x}\n{s.encode('ascii', 'replace').hex()}\n")


if __name__ == "__main__":
    main()
