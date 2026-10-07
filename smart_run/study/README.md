# OpenC906 RISC-V CPU Core Study Guide

> T-Head(Alibaba) OpenC906 64-bit RISC-V Core 학습 자료 — v2 (RTL 대조 정정 + 사이클 단위 유닛 테스트 + 스칼라 ISA/표준 보강)

## Study Structure

| Phase | Topic | Duration | Directory |
|-------|-------|----------|-----------|
| [Phase 1](./phase1_orientation/README.md) | Project Orientation & Simulation Basics (+ 유닛 테스트 환경) | Week 1 | `phase1_orientation/` |
| [Phase 2](./phase2_pipeline_frontend/README.md) | CPU Pipeline Front-End (IFU, IDU) — fetch, 분기 예측 3 단, hazard | Week 2-3 | `phase2_pipeline_frontend/` |
| [Phase 3](./phase3_pipeline_backend/README.md) | CPU Pipeline Back-End (IU, RTU) — BJU, MUL/DIV, precise exception | Week 4-5 | `phase3_pipeline_backend/` |
| [Phase 4](./phase4_memory_subsystem/README.md) | Memory Subsystem (LSU, MMU, BIU) — D$, STB, Sv39, AXI | Week 6-7 | `phase4_memory_subsystem/` |
| [Phase 5](./phase5_privileged_architecture/README.md) | Privileged Architecture & System — 모드, 위임, CLINT/PLIC, PMP | Week 8-9 | `phase5_privileged_architecture/` |
| [Phase 6](./phase6_fp_vector/README.md) | Floating-Point & Vector Extensions | Week 10-11 | `phase6_fp_vector/` |
| [Phase 7](./phase7_debug_performance/README.md) | Debug & Performance Monitoring | Week 12 | `phase7_debug_performance/` |
| [Phase 8](./phase8_soc_integration/README.md) | SoC Integration & Advanced Topics | Week 13+ | `phase8_soc_integration/` |
| [부록 A](./appendixA_scalar_isa/README.md) | RISC-V 스칼라 ISA & 표준 입문 (RVV 사용자를 위한) | Phase 2 전/병행 | `appendixA_scalar_isa/` |
| [부록 B](./appendixB_advanced/README.md) | C906 을 넘어서 — dual-issue, 분기 예측 개선, fusion, 메모리 | Phase 8 이후 | `appendixB_advanced/` |

## v2 에서 바뀐 것 (요약)

- **RTL 대조 정정**: D-Cache 4-way / I·D-Cache FIFO 교체 / BHT 는 PC 없이 전역 히스토리만 사용 / BTB 는 16-entry L0 BTB / JALR 비예측 / line fill = AXI WRAP 4 beat / CLINT·PLIC 는 CPU top 안 / PA 40bit / V 확장 비활성
- **유닛 테스트 19 개** (`unit_tests/`): Verilator 로 테스트당 약 1 초. 결과 수치 + VCD + GTKWave 세이브 파일 + 사이클 표(pipeview)
- **RTL 발췌**(파일:라인)와 **실측 수치**를 각 Phase 본문에 넣었다
- **그림**: Graphviz 구조도 11 장 + GTKWave 파형 캡처 17 장 (`figures/`, 재생성 스크립트 포함)
- **부록 A/B** 신설

## Prerequisites

- Verilog/SystemVerilog 기본 문법
- RISC-V ISA 기초 (부족하면 부록 A 부터)
- 디지털 논리 설계 기본 개념

## Environment

| Tool | Version | Purpose |
|------|---------|---------|
| verilator | 5.020 | 유닛 테스트 시뮬레이션 (빠름) |
| iverilog | 12.0 | smart_run 원본 흐름 (느림) |
| gtkwave | - | Waveform viewer |
| Surfer (WASM) | main 빌드 | 브라우저 파형 뷰어 (`make web`, Tailscale 로 접속) |
| riscv64-unknown-elf-gcc | 13.2 | Test case compilation |
| graphviz, Xvfb, ImageMagick | - | 그림 / 파형 캡처 재생성 |

## Quick Start

```bash
# 학습용 유닛 테스트 (권장)
cd openc906/smart_run/study/unit_tests
make sim                      # 최초 1 회 Verilator 빌드 (약 3~4 분)
make all                      # 19 개 테스트 → out/RESULTS.md
make run T=p2_fe02_bp_loop    # 하나만, 결과/VCD/pipeview
make wave T=p2_fe02_bp_loop   # GTKWave
make web                      # 브라우저 파형 뷰어 (태블릿/폰, tailnet 전용) — Phase 1 의 7.3 절

# smart_run 원본 흐름
cd openc906/smart_run
source ./setup/setup.sh
make runcase CASE=ISA_INT SIM=iverilog
```

## 유닛 테스트 ↔ 장 대응

| 테스트 | 주제 | 장 |
|-------|-----|----|
| u00_smoke | 환경 확인, misa/ID CSR | 1, 부록 A |
| p2_fe01_fetch_rvc | fetch 4B, RVC, I$ miss | 2, 부록 A |
| p2_fe02_bp_loop | BTB/IP/BJU redirect 비용, GHR warm-up | 2 |
| p2_fe03_bp_ghr | GHR 패턴 학습, 앨리어싱, gshare_lite 패치 | 2, 부록 B |
| p2_fe04_ras_jalr | RAS 깊이, wrong-path push, JALR | 2 |
| p3_be01_hazard | RAW/WAW stall, forward | 2, 3 |
| p3_be02_muldiv | MUL latency, DIV 가변 latency/결과 버퍼 | 3, 부록 A |
| p3_be03_mispred_penalty | mispredict penalty | 3 |
| p3_be04_trap | ecall/illegal/ebreak/비정렬 trap | 3, 5 |
| p4_mem01_dcache | hit/miss, FIFO 교체, prefetch, write-allocate, 버스 지연 | 4 |
| p4_mem02_stb | store-to-load forwarding | 4 |
| p4_mem03_amo_fence | LR/SC, AMO, fence, fence.i | 4, 부록 A |
| p4_mem04_sv39 | Sv39 walk, page fault, VIPT alias, MAEE | 4 |
| p5_sys01_priv_deleg | M/S/U 전환, medeleg | 5 |
| p5_sys02_timer_irq | CLINT 타이머/SW 인터럽트, WFI | 5 |
| p5_sys03_pmp | PMP, lock, sfence.vma | 5 |
| p5_sys04_ext_irq | TB 장치 외부 인터럽트, M vs S 진입·위임·보류, PLIC claim/complete | 5 |
| p5_sys05_ipi | IPI(CLINT MSIP), SBI 방식 S 전달, C906 SSIP0, 인터럽트 우선순위 | 5 |
| p5_sys06_wfi_flag | 인터럽트 플래그 + `while (!int_flag) { wfi; }`: 잠듦 → 인터럽트 → 플래그 → 탈출, 다른 인터럽트로 깬 경우 | 5 |
