# OpenC906 학습용 유닛 테스트

자세한 설명은 `../phase1_orientation/README.md` 의 7 절. 여기는 요약.

```bash
make sim                         # Verilator 빌드 (최초 1 회, 약 3~4 분)
make list                        # 테스트 목록
make run T=p2_fe02_bp_loop       # 한 테스트: 결과 + out/<T>/ (VCD, gtkw, pipeview.txt, trace.log, objdump)
make all                         # 전체 → out/RESULTS.md
make wave T=p2_fe02_bp_loop      # GTKWave
make web                         # 브라우저 파형 뷰어(Surfer) → tailnet 의 https://<host>:10000/  (make web-stop 으로 중지)
make run T=p2_fe03_bp_ghr PATCH=gshare_lite   # patches/gshare_lite/*.v 로 RTL 교체 빌드
make run T=... SIM=iverilog      # 원본 시뮬레이터 (느림)
```

| 도구 | 용도 |
|-----|-----|
| `tools/pipeview.py out/<T> [--mark N] [--max-rows K]` | trace.log → 사람이 읽는 사이클 표 |
| `tools/vcd_query.py <vcd> --mark N --signals a,b,c` | 구간의 신호 변화 텍스트 출력 |
| `tools/wave_snap.py out/<T> --from-cycle A --to-cycle B --signals ...  -o x.png` | 헤드리스 GTKWave 캡처 |
| `tools/collect_results.py out` | `@@ key = value` 수집 → Markdown |
| `tools/wave_web.py start\|stop\|status` | 브라우저 파형 뷰어 서버 (아래 참고) |

| 파일 | 내용 |
|-----|-----|
| `tb/study_probe.v` | 관찰 모듈 (tb.v/RTL 무수정, hierarchical reference) |
| `tb/study_tbdev.v` | TB 장치: SoC 외부 인터럽트 선 2 개 (PLIC ID 35/36) 구동. 테스트가 `TBDEV_*` 주소에 store 해서 제어 |
| `tb/soc_overlay/*.v` | `smart_run/logical` 의 같은 이름 SoC 파일 대신 쓰는 사본. `cpu_sub_system_axi.v` 는 외부 인터럽트 입력 한 줄만 다르다 |
| `tb/sim_top.v` | Verilator 래퍼 top (tb + study_probe + study_tbdev) |
| `common/crt0.S`, `lib.S`, `study.h`, `linker.ld` | 런타임, 매크로 |
| `tests/<test>/` | 테스트 19 개. 폴더마다 `<test>.S`(헤더 주석에 목적과 MARK 의미) + 실행 후 복사되는 `<test>.objdump`, `console.log`(측정값 `@@`). VCD/trace/pipeview 는 `out/<test>/` 에만 있다 |
| `patches/gshare_lite/aq_ifu_bht.v` | BHT 열 선택에 PC[3:1] XOR 하는 실험 패치 |

주의
- 콘솔 출력은 `csrw mscratch` (UART 주소가 cacheable 이라 버스로 안 나감). 테스트에서 mscratch 를 쓰지 말 것.
- `0x1FFC0~0x1FFDF` 는 TB 장치 레지스터 (store 를 테스트벤치가 감지). 버퍼로 쓰지 말 것.
- x31(t6) 은 MARK 전용.
- 사이클 수는 Verilator seed 7 (`+verilator+rand+reset+2 +verilator+seed+7`) 기준. 메모리 지연은 SoC 의 axi_fifo 모델에 의존한다.

브라우저 파형 뷰어 (`make web`)
- `web/index.html` 테스트 목록 → "파형 열기" 하면 [Surfer](https://surfer-project.org) WASM 이 브라우저에서 파형을 연다. 태블릿/폰에서도 된다.
- VCD 는 요청 시 `vcd2fst` 로 FST 로 바꿔 VCD 옆에 캐시한다 (47MB → 0.6MB). 시뮬레이션을 다시 돌리면 새로고침만 하면 된다.
- 처음 띄우는 신호는 `out/<T>/*.gtkw` 를 Surfer 명령으로 바꾼 것이다 (그룹 → divider, @24/@28/@800 → Unsigned/Binary/ASCII). MARK 마다 마커 M1, M2 ... 를 찍고 MARK 1 앞 32 사이클로 확대해서 연다. 구간 안에 trap 이 있으면 첫 trap(인터럽트가 있으면 첫 인터럽트) 앞 44 ~ 뒤 20 사이클로 연다.
- 카드의 *MARK 구간* 을 펼치면 테스트 헤더의 `MARK n : 설명` 이 나오고, `M2` 같은 링크가 그 MARK 구간으로 확대해서 연다 (`cmds/<T>/m<n>.sucl`).
- 서버는 127.0.0.1:18906 에만 열리고 `tailscale serve --https=10000` (tailnet 전용, funnel 아님) 으로만 밖에서 접근한다. 재부팅 후에는 `make web` 을 다시 실행.
- Surfer 웹 빌드는 처음 실행할 때 `web/surfer/` 로 받는다 (GitLab main 브랜치 CI 산출물). 갱신: `tools/wave_web.py fetch`.

정적 사이트 (`make site`, 서버 없이 보기)
- 공개 사이트: https://hyukyeon.github.io/openc906-waves/ (저장소 `hyukyeon/openc906-waves`, GitHub Pages).
- `make site` 가 서버가 하던 일(FST 변환, gtkw → Surfer 명령, 테스트 목록)을 미리 해서 `../../../../openc906-waves`(`SITE=` 로 변경)에 쓴다. 그 디렉터리에서 commit/push 하면 Pages 가 다시 배포한다.
  ```
  make all && make site
  cd ../../../../openc906-waves && git add -A && git commit -m "Update waves" && git push
  ```
- Pages 는 헤더를 설정할 수 없지만 Surfer 의 `sw.js` 가 필요한 헤더를 붙인다. 텍스트 파일은 `files/<T>/<kind>.txt` 로 올라간다 (Pages 는 확장자로 MIME 을 정한다).
