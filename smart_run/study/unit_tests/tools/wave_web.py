#!/usr/bin/env python3
"""out/<test>/ 의 VCD 를 브라우저(Surfer WASM 파형 뷰어)로 보여주는 작은 웹 서버.

사용: wave_web.py start | stop | status     : 백그라운드 서버 + tailscale serve (tailnet 전용 HTTPS)
      wave_web.py serve [--port N]          : 포그라운드 실행 (127.0.0.1 에만 bind)
      wave_web.py fetch                     : Surfer 웹 빌드 다운로드 -> web/surfer/
      wave_web.py sucl <x.gtkw> [x.vcd] [--mark N] : gtkw -> Surfer 명령 파일 출력 (확인용)
      wave_web.py marks <test>              : 테스트 소스의 MARK 설명 (확인용)

  * VCD 는 요청 시 vcd2fst 로 FST 로 바꿔 VCD 옆에 캐시한다 (VCD 가 더 새로우면 다시 변환).
    47MB VCD -> 약 0.6MB FST 라서 태블릿/폰에서도 바로 열린다.
  * 테스트 소스 헤더의 'MARK n : 설명' 줄을 읽어 목록에 보여 주고, MARK 마다 그 구간으로 확대해서 여는
    링크(/cmds/<test>/m<n>.sucl)를 만든다. MARK 구간 안에 trap 이 있으면 첫 trap(인터럽트 우선) 주변으로 확대한다.
  * 처음 띄울 신호는 out/<test>/*.gtkw 를 Surfer 명령으로 바꿔 넣는다.
      @800200 그룹 시작  -> divider_add + item_rename
      @24 / @28 / @800   -> item_set_format Unsigned / Binary / ASCII  (@22 hex 는 Surfer 기본값)
  * 서버는 127.0.0.1 에만 열리고, 밖에서는 tailscale serve(tailnet 전용)로만 접근한다.
"""
import argparse
import bisect
import gzip
import io
import json
import os
import re
import shutil
import signal
import socket
import subprocess
import sys
import threading
import time
import urllib.request
import zipfile
from email.utils import formatdate, parsedate_to_datetime
from http import HTTPStatus
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.parse import unquote, urlsplit

UT_DIR = Path(__file__).resolve().parent.parent
OUT_DIR = UT_DIR / "out"
TEST_DIR = UT_DIR / "tests"
WEB_DIR = UT_DIR / "web"
SURFER_DIR = WEB_DIR / "surfer"
PID_FILE = WEB_DIR / ".server.pid"
LOG_FILE = WEB_DIR / "server.log"

PORT = int(os.environ.get("WAVE_WEB_PORT", 18906))
HTTPS_PORT = int(os.environ.get("WAVE_WEB_HTTPS_PORT", 10000))
SURFER_URL = ("https://gitlab.com/surfer-project/surfer/-/jobs/artifacts/main/"
              "download?job=wasm_artifacts")

NAME_RE = re.compile(r"^[A-Za-z0-9_.-]+$")
TEXT_FILES = {"source": None, "pipeview": "pipeview.txt", "objdump": "*.objdump", "console": "console.log"}
MIME = {".html": "text/html; charset=utf-8", ".js": "text/javascript; charset=utf-8",
        ".wasm": "application/wasm", ".json": "application/json", ".ico": "image/x-icon",
        ".fst": "application/octet-stream", ".sucl": "text/plain; charset=utf-8",
        ".txt": "text/plain; charset=utf-8", ".log": "text/plain; charset=utf-8",
        ".objdump": "text/plain; charset=utf-8", ".S": "text/plain; charset=utf-8"}

# GTKWave TR_* 플래그 (gtkwave analyzer.h)
TR_HEX, TR_DEC, TR_BIN, TR_OCT = 0x2, 0x4, 0x8, 0x10
TR_BLANK, TR_SIGNED, TR_ASCII = 0x200, 0x400, 0x800
TR_GRP_BEGIN, TR_GRP_END = 0x800000, 0x1000000


MAX_MARKERS = 32
ZOOM_CYCLES = 32          # 처음 화면: MARK 구간의 앞부분 최대 32 사이클
TRAP_BEFORE = 44          # MARK 구간 안에 trap 이 있으면 그 앞 44 사이클 ~ 뒤 20 사이클
TRAP_AFTER = 20
INFO_VERSION = 3          # waveinfo.json 형식 (바뀌면 다시 만든다)
TS_PS = {"s": 10**12, "ms": 10**9, "us": 10**6, "ns": 10**3, "ps": 1, "fs": 0.001}


# ---------------------------------------------------------------- VCD 정보
def scan_vcd(vcd):
    """VCD 를 한 번 훑어 신호 이름, timescale, 클럭 주기, MARK 구간을 얻는다.

    marks: [[n, start, end, trap], ...] (VCD 시간 단위). pipeview 와 같이 0 과 리셋 직후 값(>= 2^16)은 뺀다.
      trap = 그 구간 안의 첫 인터럽트 trap(rt_expt_int) 시간, 없으면 첫 trap(rt_expt) 시간, 둘 다 없으면 None
    """
    names, scope, probe_ids, ts_text = [], [], {}, []
    in_ts = False
    with open(vcd, "r", errors="replace") as f:
        for line in f:
            tok = line.split()
            if not tok:
                continue
            if in_ts or tok[0] == "$timescale":
                in_ts = "$end" not in tok
                ts_text += [t for t in tok if not t.startswith("$")]
            elif tok[0] == "$scope" and len(tok) >= 3:
                scope.append(tok[2])
            elif tok[0] == "$upscope":
                scope.pop()
            elif tok[0] == "$var" and len(tok) >= 5:
                names.append(".".join(scope + [tok[4]]))
                if scope and scope[-1] == "study_probe" and tok[4] in ("mark", "clk", "rt_expt", "rt_expt_int"):
                    probe_ids[tok[4]] = tok[3]
            elif tok[0] == "$enddefinitions":
                break
        mark_id, clk_id = probe_ids.get("mark"), probe_ids.get("clk")
        expt_id, int_id = probe_ids.get("rt_expt"), probe_ids.get("rt_expt_int")
        t, changes, rises, traps, itraps = 0, [], [], [], []
        for line in f:
            c = line[:1]
            if c == "#":
                t = int(line[1:])
            elif c == "b" and mark_id:
                val, _, vid = line[1:].rstrip("\n").partition(" ")
                if vid == mark_id:
                    changes.append((t, int(val, 2) if val.isdigit() else None))
            elif c == "1":
                vid = line[1:].strip()
                if vid == clk_id and len(rises) < 2:
                    rises.append(t)
                elif vid == expt_id:
                    traps.append(t)
                elif vid == int_id:
                    itraps.append(t)
    m = re.match(r"(\d+)\s*([a-z]+)", "".join(ts_text))
    ts_ps = int(m.group(1)) * TS_PS.get(m.group(2), 1) if m else 1
    marks, seen = [], set()
    for i, (start, v) in enumerate(changes):
        if v is None or not 0 < v < 1 << 16 or v in seen:
            continue
        seen.add(v)
        end = changes[i + 1][0] if i + 1 < len(changes) else t
        focus = None
        for lst in (itraps, traps):
            k = bisect.bisect_left(lst, start)
            if k < len(lst) and lst[k] < end:
                focus = lst[k]
                break
        marks.append([v, start, end, focus])
    return {"v": INFO_VERSION, "names": names, "timescale_ps": ts_ps, "end": t, "marks": marks,
            "period": rises[1] - rises[0] if len(rises) == 2 else None}


# ---------------------------------------------------------------- gtkw -> Surfer 명령


def alpha_idx(i):
    """Surfer 의 표시 항목 번호 (16진수 각 자리를 a..p 로 쓴다: 0->a, 17->bb)."""
    return "".join("abcdefghijklmnop"[int(c, 16)] for c in f"{i:x}")


def surfer_format(flags, width):
    if flags & TR_ASCII:
        return "ASCII"
    if width == 1:
        return None                               # 1 비트는 Surfer 기본(Bit)
    if flags & TR_DEC:
        return "Signed" if flags & TR_SIGNED else "Unsigned"
    if flags & TR_BIN:
        return "Binary"
    if flags & TR_OCT:
        return "Octal"
    return None                                   # hex 는 Surfer 기본(Hexadecimal)


def focus_window(info, focus=None, whole=False):
    """확대할 구간 (VCD 시간 단위). focus = MARK 번호 (없으면 첫 MARK).
    whole = True 면 MARK 구간 전체 (테스트 머리 주석의 '# ZOOM: mark')."""
    marks, p = info["marks"], info["period"]
    m = next((x for x in marks if x[0] == focus), marks[0])
    start, stop = m[1], m[2]
    if whole:
        return max(0, start - 2 * p), stop + 2 * p
    trap = m[3] if len(m) > 3 else None
    if trap is not None:
        return max(start - 2 * p, trap - TRAP_BEFORE * p), min(stop, trap + TRAP_AFTER * p) + 2 * p
    return max(0, start - 2 * p), min(stop, start + ZOOM_CYCLES * p) + 2 * p


def gtkw_to_sucl(gtkw, info=None, focus=None):
    """gtkw 세이브 파일 -> Surfer 명령 줄 목록.

    info(scan_vcd 결과)가 있으면 VCD 에 없는 신호는 주석으로 남기고, MARK 마다 마커를 찍은 뒤
    MARK focus(없으면 첫 MARK) 구간으로 확대한다. 구간 안에 trap 이 있으면 첫 trap 주변으로.
    """
    known = set(info["names"]) if info else None
    # 신호를 넣을 때마다 화면을 다시 그리므로, 전체 구간(수만 사이클)이 아닌 좁은 구간에서 넣는다
    cmds = [f"# generated by tools/wave_web.py from {Path(gtkw).name}", "zoom_to 0ns 100ns"]
    idx, flags = 0, 0
    for line in Path(gtkw).read_text(errors="replace").splitlines():
        line = line.strip()
        if not line or line[0] in "[*":
            continue
        if line[0] == "@":
            flags = int(line[1:], 16)
            continue
        if line[0] == "-":
            if flags & TR_GRP_END:
                continue
            # divider_add 는 한 단어만 받으므로 만든 뒤 item_rename 으로 이름을 붙인다
            title = re.sub(r"[;#]", " ", line[1:]).strip() or "-"
            cmds += ["divider_add group", f"item_focus {alpha_idx(idx)}",
                     f"item_rename {title}", "item_unfocus"]
            idx += 1
            continue
        m = re.match(r"^(.*?)(?:\[(\d+):(\d+)\])?$", line)
        name = m.group(1)
        width = abs(int(m.group(2)) - int(m.group(3))) + 1 if m.group(2) else 1
        if known is not None and name not in known:
            cmds.append(f"# not in VCD: {line}")
            continue
        cmds.append(f"variable_add {name}")
        fmt = surfer_format(flags, width)
        if fmt:
            cmds += [f"item_focus {alpha_idx(idx)}", f"item_set_format {fmt}", "item_unfocus"]
        idx += 1
    marks = info["marks"] if info else []
    cmds += [f"marker_set M{m[0]} {m[1]}" for m in marks[:MAX_MARKERS]]
    if marks and info["period"]:
        a, b = focus_window(info, focus, test_zoom(Path(gtkw).stem) == "mark")
        ts = info["timescale_ps"]
        cmds.append(f"zoom_to {round(a * ts)}ps {round(b * ts)}ps")
    else:
        cmds.append("zoom_fit")
    return cmds


# ---------------------------------------------------------------- out/ 탐색
def test_files(name):
    """out/<name>/ 의 (vcd, gtkw) 경로. 변형 빌드(PATCH=..)는 디렉터리 이름이 <test>_<patch>."""
    d = OUT_DIR / name
    if not NAME_RE.match(name) or not d.is_dir():
        return None, None
    vcds = sorted(d.glob("*.vcd"))
    vcd = next((v for v in vcds if v.stem == name), vcds[0] if vcds else None)
    gtkws = sorted(d.glob("*.gtkw"))
    gtkw = next((g for g in gtkws if vcd and g.stem == vcd.stem), gtkws[0] if gtkws else None)
    return vcd, gtkw


def test_title(stem):
    src = TEST_DIR / stem / f"{stem}.S"
    if src.exists():
        for line in src.read_text(errors="replace").splitlines()[:5]:
            m = re.match(rf"^#\s*{re.escape(stem)}\s*:\s*(.+)$", line)
            if m:
                return m.group(1).strip()
    return ""


def test_zoom(stem):
    """테스트 머리 주석의 '# ZOOM: mark' -> "mark" (MARK 구간 전체를 보여 준다). 없으면 None (trap 주변 확대)."""
    src = TEST_DIR / stem / f"{stem}.S"
    if src.exists():
        for line in src.read_text(errors="replace").splitlines():
            if line.strip() and not line.startswith("#"):
                break
            m = re.match(r"^#\s*ZOOM:\s*(\w+)", line)
            if m:
                return m.group(1)
    return None


MARK_RE = re.compile(r"MARK\s+(\d+(?:\s*(?:/|\.\.|,)\s*\d*)*)\s*:\s*")


def mark_numbers(spec):
    """'1' -> [1], '4/5' -> [4, 5], '1..8' -> [1..8], '10..' -> [10]."""
    m = re.fullmatch(r"(\d+)\s*\.\.\s*(\d+)", spec)
    if m:
        a, b = int(m.group(1)), int(m.group(2))
        return list(range(a, b + 1)) if 0 <= b - a < 32 else [a]
    return [int(x) for x in re.findall(r"\d+", spec)]


def test_marks(stem):
    """테스트 소스 머리 주석의 MARK 설명 -> [{"ns": [n, ...], "desc": "..."}, ...] (MARK 번호 순)

    지원 형식:  '#  MARK 1 : 설명'  '#  MARK 4/5 : ...'  '#  MARK 1..8 : ...'  한 줄에 MARK 두 개,
               '#   설명 ...  -> MARK 3' (p5_sys01)
    """
    src = TEST_DIR / stem / f"{stem}.S"
    if not src.exists():
        return []
    out, seen = [], set()
    for line in src.read_text(errors="replace").splitlines():
        if not line.startswith("#"):
            if line.strip():
                break                                  # 머리 주석 끝
            continue
        text = line.lstrip("#").strip()
        found = list(MARK_RE.finditer(text))
        items = []
        if found and found[0].start() == 0:
            for i, m in enumerate(found):
                end = found[i + 1].start() if i + 1 < len(found) else len(text)
                items.append((mark_numbers(m.group(1)), text[m.end():end].strip()))
        else:
            m = re.search(r"^(.*?)\s*->\s*MARK\s+(\d+)\s*$", text)
            if m:
                items.append(([int(m.group(2))], m.group(1).strip()))
        for ns, desc in items:
            ns = [n for n in ns if n not in seen]
            if ns and desc:
                seen.update(ns)
                out.append({"ns": ns, "desc": re.sub(r"\s{2,}", "  ", desc)})
    return sorted(out, key=lambda x: x["ns"][0])


def gtkw_groups(gtkw):
    groups, flags = [], 0
    for line in gtkw.read_text(errors="replace").splitlines():
        if line.startswith("@"):
            flags = int(line[1:], 16)
        elif line.startswith("-") and flags & TR_GRP_BEGIN:
            groups.append(line[1:].strip())
    return groups


def list_tests():
    tests = []
    for d in sorted(OUT_DIR.iterdir()) if OUT_DIR.is_dir() else []:
        vcd, gtkw = test_files(d.name)
        if not vcd:
            continue
        st = vcd.stat()
        report = d / "run_case.report"
        result = None
        if report.exists():
            result = "PASS" if "TEST PASS" in report.read_text(errors="replace") else "FAIL"
        fst = vcd.with_suffix(".fst")
        tests.append({
            "name": d.name,
            "stem": vcd.stem,
            "variant": d.name[len(vcd.stem) + 1:] if d.name.startswith(vcd.stem + "_") else "",
            "title": test_title(vcd.stem),
            "result": result,
            "vcd_size": st.st_size,
            "fst_size": fst.stat().st_size if fst.exists() else None,
            "mtime": int(st.st_mtime),
            "groups": gtkw_groups(gtkw) if gtkw else [],
            "marks": test_marks(vcd.stem),
            "files": [k for k in TEXT_FILES if text_file(d.name, k)],
        })
    return tests


def text_file(name, kind):
    if kind == "source":                     # tests/<test>/<test>.S (변형 빌드는 원래 테스트의 소스)
        vcd, _ = test_files(name)
        src = TEST_DIR / vcd.stem / f"{vcd.stem}.S" if vcd else None
        return src if src and src.exists() else None
    pattern = TEXT_FILES.get(kind)
    found = sorted((OUT_DIR / name).glob(pattern)) if pattern else []
    return found[0] if found else None


_locks = {}
_locks_guard = threading.Lock()


def ensure_derived(vcd):
    """VCD 옆에 <stem>.fst 와 <stem>.waveinfo.json(scan_vcd 결과)을 만든다. VCD 가 더 새로우면 다시."""
    fst, info_f = vcd.with_suffix(".fst"), vcd.with_suffix(".waveinfo.json")
    with _locks_guard:
        lock = _locks.setdefault(str(vcd), threading.Lock())
    with lock:
        vt = vcd.stat().st_mtime
        if not fst.exists() or fst.stat().st_mtime < vt:
            tmp = fst.with_name(fst.stem + ".tmp.fst")
            subprocess.run(["vcd2fst", str(vcd), str(tmp)], check=True,
                           stdout=subprocess.DEVNULL, stderr=subprocess.PIPE)
            os.replace(tmp, fst)
        info = json.loads(info_f.read_text()) if info_f.exists() and info_f.stat().st_mtime >= vt else {}
        if info.get("v") != INFO_VERSION:
            info = scan_vcd(vcd)
            info_f.write_text(json.dumps(info))
    return fst, info


# ---------------------------------------------------------------- HTTP
class Handler(BaseHTTPRequestHandler):
    server_version = "c906-wave-web"

    def log_message(self, fmt, *args):
        sys.stderr.write("%s %s\n" % (time.strftime("%H:%M:%S"), fmt % args))

    def end_headers(self):
        # 시뮬레이션을 다시 돌리면 같은 URL 의 내용이 바뀌므로 항상 재검증하게 한다
        self.send_header("Cache-Control", "no-cache")
        super().end_headers()

    def do_GET(self):
        path = unquote(urlsplit(self.path).path)
        try:
            if path in ("/", "/index.html"):
                return self.send_file(WEB_DIR / "index.html")
            if path == "/api/tests":
                return self.send_bytes(json.dumps(list_tests()).encode(), "application/json")
            if path.startswith("/surfer/") or path == "/surfer":
                return self.send_static(SURFER_DIR, path[len("/surfer/"):] or "index.html")
            m = re.match(r"^/(waves|cmds)/([^/]+)\.(fst|sucl)$", path)
            if m:
                return self.send_test(*m.groups())
            m = re.match(r"^/cmds/([^/]+)/m(\d+)\.sucl$", path)
            if m:
                return self.send_test("cmds", m.group(1), "sucl", int(m.group(2)))
            m = re.match(r"^/files/([^/]+)/(\w+)$", path)
            if m:
                f = text_file(m.group(1), m.group(2)) if NAME_RE.match(m.group(1)) else None
                return self.send_file(f) if f else self.send_error(HTTPStatus.NOT_FOUND)
            self.send_error(HTTPStatus.NOT_FOUND)
        except (BrokenPipeError, ConnectionResetError):
            pass
        except subprocess.CalledProcessError as e:
            self.send_error(HTTPStatus.INTERNAL_SERVER_ERROR, "vcd2fst failed",
                            e.stderr.decode(errors="replace")[-500:])

    def send_test(self, kind, name, ext, focus=None):
        vcd, gtkw = test_files(name)
        if not vcd or (kind, ext) not in (("waves", "fst"), ("cmds", "sucl")):
            return self.send_error(HTTPStatus.NOT_FOUND)
        fst, info = ensure_derived(vcd)
        if kind == "waves":
            return self.send_file(fst)
        cmds = gtkw_to_sucl(gtkw, info, focus) if gtkw else ["zoom_fit"]
        self.send_bytes(("\n".join(cmds) + "\n").encode(), MIME[".sucl"])

    def send_static(self, root, rel):
        f = (root / rel).resolve()
        if root.resolve() not in f.parents or not f.is_file():
            return self.send_error(HTTPStatus.NOT_FOUND)
        extra = {}
        if rel.endswith("index.html") or rel.endswith(".js") or rel.endswith(".wasm"):
            # Surfer sw.js 가 붙이는 것과 같은 헤더 (cross-origin isolation)
            extra = {"Cross-Origin-Opener-Policy": "same-origin",
                     "Cross-Origin-Embedder-Policy": "require-corp"}
        gz = f.with_name(f.name + ".gz")
        if gz.exists() and "gzip" in self.headers.get("Accept-Encoding", ""):
            extra["Content-Encoding"] = "gzip"
            extra["Vary"] = "Accept-Encoding"
            return self.send_file(gz, MIME.get(f.suffix), extra)
        self.send_file(f, None, extra)

    def send_file(self, f, ctype=None, extra=None):
        st = f.stat()
        ims = self.headers.get("If-Modified-Since")
        if ims:
            try:
                if int(st.st_mtime) <= parsedate_to_datetime(ims).timestamp():
                    self.send_response(HTTPStatus.NOT_MODIFIED)
                    self.end_headers()
                    return
            except (TypeError, ValueError):
                pass
        self.send_response(HTTPStatus.OK)
        self.send_header("Content-Type", ctype or MIME.get(f.suffix, "application/octet-stream"))
        self.send_header("Content-Length", str(st.st_size))
        self.send_header("Last-Modified", formatdate(st.st_mtime, usegmt=True))
        for k, v in (extra or {}).items():
            self.send_header(k, v)
        self.end_headers()
        with open(f, "rb") as fp:
            shutil.copyfileobj(fp, self.wfile)

    def send_bytes(self, data, ctype):
        self.send_response(HTTPStatus.OK)
        self.send_header("Content-Type", ctype)
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)


# ---------------------------------------------------------------- 명령
def fetch_surfer():
    print(f"downloading Surfer web build: {SURFER_URL}")
    with urllib.request.urlopen(SURFER_URL, timeout=120) as r:
        data = r.read()
    tmp = WEB_DIR / "surfer.tmp"
    shutil.rmtree(tmp, ignore_errors=True)
    tmp.mkdir(parents=True)
    with zipfile.ZipFile(io.BytesIO(data)) as z:
        for info in z.infolist():
            if info.is_dir() or not info.filename.startswith("surfer_wasm/"):
                continue
            (tmp / Path(info.filename).name).write_bytes(z.read(info))
    # trunk 가 /dist/ 기준으로 빌드한 것을 상대 경로로 (Surfer CI 의 pages_build 와 같은 처리)
    index = tmp / "index.html"
    index.write_text(index.read_text().replace("/dist/", "./"))
    for name in ("surfer_bg.wasm", "surfer.js"):
        with open(tmp / name, "rb") as src, gzip.open(tmp / (name + ".gz"), "wb", 9) as dst:
            shutil.copyfileobj(src, dst)
    (tmp / "VERSION").write_text(f"{SURFER_URL}\ndownloaded {time.strftime('%Y-%m-%d %H:%M:%S %z')}\n")
    shutil.rmtree(SURFER_DIR, ignore_errors=True)
    tmp.rename(SURFER_DIR)
    print(f"  -> {SURFER_DIR}")


def serve(port):
    if not (SURFER_DIR / "index.html").exists():
        fetch_surfer()
    httpd = ThreadingHTTPServer(("127.0.0.1", port), Handler)
    print(f"serving {UT_DIR} on http://127.0.0.1:{port}/", flush=True)
    httpd.serve_forever()


def running_pid():
    try:
        pid = int(PID_FILE.read_text())
        os.kill(pid, 0)
        return pid
    except (OSError, ValueError):
        return None


def tailnet_url():
    try:
        out = subprocess.run(["tailscale", "status", "--json"], capture_output=True, check=True)
        host = json.loads(out.stdout)["Self"]["DNSName"].rstrip(".")
        return f"https://{host}:{HTTPS_PORT}/"
    except (OSError, subprocess.CalledProcessError, KeyError, ValueError):
        return None


def start():
    if not (SURFER_DIR / "index.html").exists():
        fetch_surfer()
    pid = running_pid()
    if pid:
        print(f"server already running (pid {pid})")
    else:
        log = open(LOG_FILE, "ab")
        p = subprocess.Popen([sys.executable, __file__, "serve", "--port", str(PORT)],
                             stdout=log, stderr=subprocess.STDOUT, stdin=subprocess.DEVNULL,
                             start_new_session=True)
        PID_FILE.write_text(str(p.pid))
        for _ in range(50):
            try:
                socket.create_connection(("127.0.0.1", PORT), timeout=0.2).close()
                break
            except OSError:
                if p.poll() is not None:
                    sys.exit(f"server exited, see {LOG_FILE}")
                time.sleep(0.1)
        print(f"server started (pid {p.pid}), log: {LOG_FILE}")
    # tailnet 전용 (funnel 아님). 같은 머신의 다른 serve 설정(443 등)은 건드리지 않는다.
    subprocess.run(["tailscale", "serve", "--bg", "--yes", f"--https={HTTPS_PORT}",
                    f"http://127.0.0.1:{PORT}"], check=True, stdout=subprocess.DEVNULL)
    print(f"open: {tailnet_url() or f'https://<this host>:{HTTPS_PORT}/'}  (tailnet only)")


def stop():
    subprocess.run(["tailscale", "serve", f"--https={HTTPS_PORT}", "off"],
                   stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    pid = running_pid()
    if pid:
        os.kill(pid, signal.SIGTERM)
        print(f"server stopped (pid {pid})")
    else:
        print("server not running")
    PID_FILE.unlink(missing_ok=True)


def status():
    pid = running_pid()
    print(f"server : {'running, pid %d' % pid if pid else 'stopped'}  (127.0.0.1:{PORT})")
    out = subprocess.run(["tailscale", "serve", "status"], capture_output=True, text=True).stdout
    on = f":{HTTPS_PORT}" in out
    print(f"serve  : {tailnet_url() if on else 'off'}")


def main():
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    sub = ap.add_subparsers(dest="cmd", required=True)
    for c in ("start", "stop", "status", "fetch"):
        sub.add_parser(c)
    p = sub.add_parser("serve")
    p.add_argument("--port", type=int, default=PORT)
    p = sub.add_parser("sucl")
    p.add_argument("gtkw")
    p.add_argument("vcd", nargs="?")
    p.add_argument("--mark", type=int, help="이 MARK 구간으로 확대")
    p = sub.add_parser("marks")
    p.add_argument("stem")
    a = ap.parse_args()
    if a.cmd == "serve":
        serve(a.port)
    elif a.cmd == "sucl":
        print("\n".join(gtkw_to_sucl(a.gtkw, scan_vcd(a.vcd) if a.vcd else None, a.mark)))
    elif a.cmd == "marks":
        print(json.dumps(test_marks(a.stem), ensure_ascii=False, indent=1))
    else:
        {"start": start, "stop": stop, "status": status, "fetch": fetch_surfer}[a.cmd]()


if __name__ == "__main__":
    main()
