# Phase 8: SoC Integration & Advanced Topics

> **기간**: Week 13+
> **목표**: SoC 전체 통합 구조를 이해하고, 커스텀 테스트 작성 및 성능 분석을 수행한다.
> ⚠️ v2 정정: (1) CLINT/PLIC 는 SoC 버스의 슬레이브가 아니라 **CPU top(openC906) 안**에 있다 (2) SRAM 모델은 8MB × 2 (3) SoC 의 메모리 지연 모델(axi_fifo)과 그 영향(Phase 4 의 5 절) (4) 커스텀 테스트는 유닛 테스트 환경 사용을 권장(4.4 절) (5) 2-issue 등 고급 주제는 부록 B.

---

## 1. SoC Architecture

### 1.1 SoC Block Diagram

```
┌──────────────────────────────── SoC (smart_run/logical/common/soc.v) ─────────────────────────────┐
│                                                                                                     │
│  ┌──────────── x_cpu_sub_system_axi ─────────────┐                                                 │
│  │  x_c906_wrapper → x_cpu_top (openC906)        │                                                 │
│  │   ├ aq_top : core(IFU..RTU, FPU) · MMU · PMP  │                                                 │
│  │   ├ aq_biu_top (AXI4 128bit master)           │                                                 │
│  │   ├ clint_top  ← 0x40_0400_0000               │                                                 │
│  │   ├ plic_top   ← 0x40_0000_0000               │                                                 │
│  │   └ tdt_top (Debug Module, JTAG)              │                                                 │
│  └───────────────────┬───────────────────────────┘                                                 │
│                      │ AXI (128bit)                                                                 │
│              ┌───────▼────────┐  AR 채널만 지연 FIFO 통과                                            │
│              │   x_axi_fifo   │  (0x0~0x1FFFF: bus_delay 레지스터 값 / 그 외: 0~200 cycle 가변)       │
│              └───────┬────────┘                                                                    │
│              ┌───────▼──────────────┐                                                              │
│              │ AXI interconnect     │                                                              │
│              └──┬────────────────┬──┘                                                              │
│          ┌──────▼─────┐   ┌──────▼──────┐                                                          │
│          │ SRAM 8MB×2 │   │ AXI → AHB   │ → AHB → APB : UART(0x1001_5000) GPIO timer              │
│          │ (axi_slave)│   └─────────────┘                bus_delay(0x1001_A000) …                  │
│          └────────────┘                                                                            │
└─────────────────────────────────────────────────────────────────────────────────────────────────────┘
```

### 1.2 Bus Hierarchy

```
CPU (openC906)
 ├── 내부 : CLINT, PLIC  (BIU 의 apbif 경로, sysmap 구간 6 = device)
 └── AXI4 128bit master
      └── axi_fifo (읽기 지연 모델)
           └── AXI interconnect
                ├── SRAM (f_spsram_524288x128 × 2 = 8MB × 2)
                └── AXI → AHB (32bit) → AHB → APB
                     ├── UART      0x1001_5000
                     ├── GPIO
                     ├── timer
                     └── bus_delay 0x1001_A000  (axi_fifo 의 읽기 지연 값)
```

---

## 2. Bus Protocols

### 2.1 AXI (Advanced eXtensible Interface)

```
smart_run/logical/axi/ (6 files)
```

```
AXI4 Features in C906 SoC:
┌─────────────────────────────────────────────┐
│ Data Width    : 128 bits (16 bytes)         │
│ Address Width : 40 bits                     │
│ Burst Type    : INCR (incrementing)         │
│ Burst Length  : up to 16 beats              │
│ ID Width      : configurable                │
│ Outstanding   : multiple transactions       │
└─────────────────────────────────────────────┘

AXI Transaction Flow (Read):
  Master                              Slave
    │  AR channel (address + control)   │
    │ ─────────────────────────────────→│
    │                                   │
    │  R channel (data + response)      │
    │ ←─────────────────────────────────│
    │ ←─────────────────────────────────│  (burst beats)
    │ ←─────────────────────────────────│
    │ ←──────────────────(RLAST)────────│

AXI Transaction Flow (Write):
  Master                              Slave
    │  AW channel (address + control)   │
    │ ─────────────────────────────────→│
    │  W channel (data + strobe)        │
    │ ─────────────────────────────────→│
    │ ─────────────────────────────────→│  (burst beats)
    │ ───────────────(WLAST)───────────→│
    │                                   │
    │  B channel (write response)       │
    │ ←─────────────────────────────────│
```

#### AXI Interconnect (`axi_interconnect128.v`)

```
Address Decoding:
  요청 주소를 기반으로 적절한 slave로 라우팅

  Address Map (이 SoC):
  ┌─────────────────────┬──────────────────────────────────────┐
  │ 0x00_0000_0000 ~    │ SRAM (프로그램 0x0, 데이터 0x40000 ~)  │
  │ 0x00_1001_5000      │ UART (APB)                            │
  │ 0x00_1001_A000      │ bus_delay 레지스터 (APB)               │
  │ 0x40_0000_0000      │ PLIC  (CPU 내부, pad_cpu_apb_base)     │
  │ 0x40_0400_0000      │ CLINT (CPU 내부, base + 0x400_0000)     │
  └─────────────────────┴──────────────────────────────────────┘
```

### 2.2 AHB (Advanced High-performance Bus)

```
smart_run/logical/ahb/ (2 files)
```

```
AHB Signals:
┌──────────┬──────────────────────────────┐
│ HADDR    │ Address                      │
│ HTRANS   │ Transfer type (IDLE/NONSEQ)  │
│ HWRITE   │ Write(1) / Read(0)           │
│ HSIZE    │ Transfer size                │
│ HWDATA   │ Write data                   │
│ HRDATA   │ Read data                    │
│ HREADY   │ Transfer complete            │
│ HRESP    │ Response (OK/ERROR)          │
└──────────┴──────────────────────────────┘

특징:
- Pipelined: address phase와 data phase 분리
- Single master (이 SoC에서는)
- AXI보다 단순 (outstanding 미지원)
```

### 2.3 APB (Advanced Peripheral Bus)

```
smart_run/logical/apb/ (2 files)
```

```
APB Signals:
┌──────────┬──────────────────────────────┐
│ PADDR    │ Address                      │
│ PSEL     │ Slave select                 │
│ PENABLE  │ Enable (2nd cycle)           │
│ PWRITE   │ Write(1) / Read(0)           │
│ PWDATA   │ Write data                   │
│ PRDATA   │ Read data                    │
│ PREADY   │ Slave ready                  │
└──────────┴──────────────────────────────┘

APB Transfer (2 cycles):
  Cycle 1 (Setup): PSEL=1, PENABLE=0, address/data 설정
  Cycle 2 (Access): PENABLE=1, data transfer
  → 가장 단순한 AMBA 프로토콜, 저속 주변장치용
```

---

## 3. Peripherals

### 3.1 UART (`smart_run/logical/uart/`)

```
UART Files:
├── uart.v            # UART top
├── uart_ctrl.v       # Control logic
├── uart_apb_reg.v    # APB register interface
├── uart_baud_gen.v   # Baud rate generator
├── uart_trans.v      # Transmitter
└── uart_receive.v    # Receiver

UART은 시뮬레이션에서 printf 출력 용도:
- CPU가 UART data register (0x10015000)에 byte write
- tb.v가 이를 감지하여 $write()로 콘솔 출력
```

### 3.2 GPIO (`smart_run/logical/gpio/`)

```
GPIO Files:
├── gpio.v            # GPIO top
├── gpio_ctrl.v       # Control logic
└── gpio_apbif.v      # APB register interface

8-bit GPIO port (b_pad_gpio_porta)
- Input/Output 방향 설정 가능
- 인터럽트 지원
```

### 3.3 Memory Model (`smart_run/logical/mem/`)

```
Memory Files:
├── ram.v                    # Basic RAM model
├── mem_ctrl.v               # Memory controller
├── f_spsram_32768x128.v     # 32K×128bit SRAM
└── f_spsram_524288x128.v    # 512K×128bit SRAM (main memory)

시뮬레이션 메모리:
- f_spsram_524288x128 × 2 = 8MB × 2 (524288 × 16B)
- 내부적으로 16개의 byte-wide RAM으로 구성
  (ram0 ~ ram15, 각 8-bit × 16 = 128-bit)
- tb.v에서 inst.pat, data.pat을 여기에 로드
```

---

## 4. Custom Test Case 작성

### 4.1 Assembly Test Case 작성법

```asm
# my_test.s - Custom test case example

.section .text
.globl _start

_start:
    # ===== Test: ADD instruction =====
    li   x1, 100          # x1 = 100
    li   x2, 200          # x2 = 200
    add  x3, x1, x2      # x3 = 300

    # Check result
    li   x4, 300
    bne  x3, x4, fail     # if x3 != 300, fail

    # ===== Test: Memory access =====
    la   x5, test_data
    sd   x1, 0(x5)        # store 100
    ld   x6, 0(x5)        # load back
    bne  x6, x1, fail     # verify

    # ===== PASS =====
    li   x1, 0x444333222  # Magic pass value
    j    end

fail:
    li   x1, 0x2382348720 # Magic fail value

end:
    nop
    j    end               # Loop forever (tb detects magic value)

.section .data
test_data:
    .dword 0
```

### 4.2 Test Case 등록

```bash
# 1. 테스트 파일 배치
mkdir -p tests/cases/custom/
cp my_test.s tests/cases/custom/

# 2. smart_cfg.mk에 케이스 추가
# CASE_LIST에 custom 추가
# custom_build 타겟 추가
```

**smart_cfg.mk에 추가할 내용:**

```makefile
CASE_LIST := \
    ...existing cases... \
    custom

custom_build:
    @cp ./tests/cases/custom/* ./work
    @find ./tests/lib/ -maxdepth 1 -type f -exec cp {} ./work/ \;
    @cd ./work && make -s clean && make -s all \
        CPU_ARCH_FLAG_0=c906fd \
        ENDIAN_MODE=little-endian \
        CASENAME=custom \
        FILE=my_test >& custom_build.case.log
```

### 4.3 실행

```bash
make runcase CASE=custom SIM=iverilog DUMP=on
cat work/run_case.report
gtkwave work/test.vcd
```

---

### 4.4 (권장) 유닛 테스트 환경으로 작성하기

smart_run 의 케이스 등록 방식 대신 `smart_run/study/unit_tests` 에 `tests/<이름>/<이름>.S` 파일 하나만 두면 된다 (Phase 1 의 7 절).

```bash
cd smart_run/study/unit_tests
mkdir tests/my_test && cp tests/u00_smoke/u00_smoke.S tests/my_test/my_test.S   # 편집
make run T=my_test                     # 약 1 초: 결과, VCD, gtkw, pipeview
```

- 측정은 `TIC/TOC`, 구간 표시는 `MARK(n)`, 결과는 `REPORT "이름", reg`.
- PASS/FAIL 은 crt0 의 `pass`/`fail` 로 점프 (tb.v 의 magic value 방식을 그대로 사용).

## 5. Performance Analysis

### 5.1 CoreMark Benchmark

```bash
make runcase CASE=coremark SIM=iverilog
```

```
CoreMark 구성:
- tests/cases/coremark/core_main.c    → 메인 루프
- tests/cases/coremark/core_matrix.c  → 행렬 연산
- tests/cases/coremark/core_list_join.c → 링크드 리스트
- tests/cases/coremark/core_state.c   → 상태 머신
- tests/cases/coremark/core_util.c    → 유틸리티

성능 지표:
  CoreMark/MHz = iterations / (time_in_seconds × frequency)
  C906 reference: ~5.0 CoreMark/MHz (typical)
```

### 5.2 IPC Profiling

```
파형에서 IPC 분석:

1. retire 신호 관찰 기간 결정 (start_cycle ~ end_cycle)
2. 해당 구간의 retire 횟수 카운트
3. IPC = retire_count / (end_cycle - start_cycle)

IPC 저하 원인 분석:
┌──────────────────────┬─────────────────────────────┐
│ Symptom              │ Likely Cause                │
├──────────────────────┼─────────────────────────────┤
│ Long stall, no retire│ D-Cache miss (memory access)│
│ Burst of flush       │ Branch misprediction        │
│ Periodic stall       │ I-Cache miss                │
│ Short stall          │ RAW data hazard             │
│ Very long stall      │ DIV instruction             │
│ Multi-cycle gap      │ FP operation (FDIV, FSQRT)  │
└──────────────────────┴─────────────────────────────┘
```

### 5.3 Cache Performance Analysis

```
Cache Hit Rate 분석:

I-Cache:
  total_access = I-Cache access count
  miss_count = I-Cache miss count (BIU read for I-Cache)
  hit_rate = (total_access - miss_count) / total_access × 100%

D-Cache:
  total_access = Load + Store count
  miss_count = D-Cache miss count (LFB activation)
  hit_rate = (total_access - miss_count) / total_access × 100%

목표: > 95% hit rate (일반적인 워크로드)
```

---

## 6. Advanced Topics

### 6.1 Clock Gating

```
gated_clk_cell.v (gen_rtl/clk/rtl/):
  - 사용하지 않는 모듈의 clock을 차단
  - Dynamic power 절감
  - ICG (Integrated Clock Gating) cell 사용

구조:
  clk_in → [AND gate with latch] → clk_out
  enable ──┘

  enable=0 → clk_out stays low (no switching → no dynamic power)
```

### 6.2 Reset Architecture

```
aq_mp_rst_top.v (gen_rtl/rst/rtl/):
  - Asynchronous assert, synchronous deassert
  - Reset 해제 시 clock과 동기화하여 metastability 방지

Reset Sequence:
  1. External reset assert (async)
  2. Internal reset propagation
  3. Clock stabilization
  4. Reset deassert (synced to clock edge)
  5. CPU starts from reset vector (PC = 0x0)
```

### 6.3 FPGA Implementation

```
gen_rtl/fpga/rtl/ (9 files):
  - ASIC SRAM을 FPGA Block RAM으로 대체
  - fpga_ram.v: generic RAM model for FPGA
  - aq_f_spsram_*.v: 각 크기별 FPGA SRAM

FPGA 구현 시 고려사항:
  1. Clock: FPGA PLL로 생성
  2. SRAM: Block RAM / Distributed RAM 매핑
  3. IO: JTAG, UART, GPIO 핀 할당
  4. Timing: SDC 파일 (impl/sdc/) 참조
```

### 6.4 Waveform Analysis Tips

```
GTKWave 활용 팁:

1. Signal Grouping:
   - Pipeline stage별로 그룹화
   - Clock + Reset을 맨 위에 배치

2. Key Signals to Always Include:
   - clk, rst_b
   - core0_pad_retire, retire_pc
   - biu_pad_araddr, biu_pad_awaddr (bus activity)

3. Marker 활용:
   - 관심 시점에 marker 설정
   - 두 marker 간 cycle 수 측정

4. Filter:
   - 특정 값이 나타나는 시점 검색
   - Trigger condition 설정

5. Save/Load:
   - .gtkw 파일로 signal 설정 저장
   - 반복 분석 시 재사용
```

---

## 7. Simulation Exercises

### Lab 8.1: Bus Transaction 추적

```bash
make runcase CASE=ISA_LS SIM=iverilog DUMP=on
```

- [ ] AXI read transaction: AR channel → R channel burst
- [ ] AXI write transaction: AW + W channel → B channel
- [ ] AXI → AHB → APB 전파 과정 (UART write 시)

### Lab 8.2: Custom Test Case 작성 및 실행

- [ ] 간단한 assembly test 작성 (add, load, store, branch)
- [ ] smart_cfg.mk에 등록
- [ ] `make runcase CASE=custom SIM=iverilog DUMP=on`
- [ ] 파형에서 자신의 명령어 실행 추적

### Lab 8.3: CoreMark 실행 및 분석

```bash
make runcase CASE=coremark SIM=iverilog
```

- [ ] CoreMark 결과 확인 (iterations, time)
- [ ] CoreMark/MHz 계산
- [ ] 핫스팟 구간 IPC 분석

### Lab 8.4: 종합 성능 분석

- [ ] 전체 테스트 케이스 regress 실행: `make regress`
- [ ] 각 테스트의 실행 시간 비교
- [ ] 가장 느린 테스트의 bottleneck 분석

---

## 8. Further Study

### 8.1 관련 프로젝트

| Project | Description |
|---------|-------------|
| OpenC910 | T-Head dual-issue, out-of-order core |
| BOOM | Berkeley OoO RISC-V core (Chisel) |
| Rocket | Berkeley in-order RISC-V core (Chisel) |
| CVA6 (Ariane) | 6-stage in-order RISC-V core |
| XiangShan | 중국 고성능 OoO RISC-V (Chisel) |

### 8.2 추천 학습 자료

| Topic | Resource |
|-------|----------|
| RISC-V ISA | "The RISC-V Reader" (Patterson & Waterman) |
| CPU Architecture | "Computer Organization and Design: RISC-V" (H&P) |
| Cache Design | "Memory Systems: Cache, DRAM, Disk" (Jacob et al.) |
| Verilog | "Digital Design and Computer Architecture: RISC-V" |
| AXI Protocol | ARM AMBA AXI Protocol Specification |
| Debug Spec | RISC-V Debug Specification v0.13 |

### 8.3 다음 단계 도전 과제

- [ ] C906에 custom instruction 추가
- [ ] Cache 크기 변경 후 성능 비교
- [ ] 2-issue superscalar로 확장 설계 (conceptual) → 부록 B 의 1 절
- [ ] BHT 에 PC 해시 추가 실험 → 부록 B 의 2 절 (`PATCH=gshare_lite`)
- [ ] FPGA 보드에 C906 SoC 구현
- [ ] Linux 부팅 (with MMU, CLINT, PLIC)
- [ ] OpenC910 (out-of-order)과 구조 비교 분석

---

## 9. Checklist

- [ ] SoC 전체 버스 계층 (AXI → AHB → APB)을 그릴 수 있다
- [ ] AXI의 5개 채널과 동작 방식을 설명할 수 있다
- [ ] AHB와 APB의 차이점을 설명할 수 있다
- [ ] UART를 통한 시뮬레이션 printf 메커니즘을 설명할 수 있다
- [ ] 커스텀 어셈블리 테스트를 작성하고 실행할 수 있다
- [ ] CoreMark/MHz의 의미를 설명할 수 있다
- [ ] IPC 저하 원인을 분석할 수 있다
- [ ] Cache hit rate를 측정하고 해석할 수 있다
- [ ] Clock gating의 목적과 구현 방법을 설명할 수 있다
