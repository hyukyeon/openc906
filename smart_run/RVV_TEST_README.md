# RVV Vector Firmware Test — QEMU vs RTL 비교 환경

SPIKE 없이 RISC-V Vector 펌웨어를 검증하는 환경입니다.
- **QEMU 경로**: `qemu-riscv64`로 rv64v 펌웨어를 실행 (SPIKE 불필요)
- **RTL 경로**: OpenC906 RTL + iverilog로 동일 알고리즘을 하드웨어 시뮬레이션
- **비교**: 양쪽 모두 `RESULT: PASS`를 확인하여 펌웨어 동작을 검증

---

## 디렉토리 구조

```
smart_run/
├── tests/cases/ISA/ISA_VECTOR/
│   ├── rvv_vadd_smoke.s     # RTL용 rv64v 어셈블리 테스트
│   └── crt0_v.s             # GCC 13 호환 startup (mxstatus → 0x7c0)
│
├── qemu_tests/
│   ├── src/rvv_vadd.c       # QEMU용 rv64v C 테스트 (동일 알고리즘)
│   ├── src/sys/io.c         # nostdlib printf (Linux ecall 기반)
│   └── Makefile             # qemu-riscv64 빌드/실행
│
├── setup/smart_cfg.mk       # ISA_VECTOR CASE_LIST + 빌드 규칙 추가
├── compare.sh               # QEMU + RTL 결과 비교 스크립트
└── RVV_TEST_README.md       # 이 파일
```

---

## 테스트 알고리즘

```
C[i] = A[i] + B[i]  (i = 0..7, int32, vadd.vv)

A   = {1, 2, 3, 4, 5, 6, 7, 8}
B   = {10, 20, 30, 40, 50, 60, 70, 80}
기대 = {11, 22, 33, 44, 55, 66, 77, 88}
```

---

## 빠른 시작

### 1. QEMU 테스트 (SPIKE 없이 즉시 실행)

```bash
cd qemu_tests
make            # rv64imafdcv로 빌드
make run-rvv_vadd

# 예상 출력:
# === RVV VADD TEST (rv64v/qemu) ===
#  i |  A |  B |  C | EXP | CHK
# ---+----+----+----+-----+----
#  0 |  1 | 10 | 11 |  11 | OK
#  ...
#  7 |  8 | 80 | 88 |  88 | OK
# RESULT: PASS
```

### 2. RTL 테스트 (OpenC906 iverilog 시뮬레이션)

```bash
# 환경 설정 (CODE_BASE_PATH, TOOL_EXTENSION 자동 설정)
source ./setup/setup.sh

# RTL 컴파일 (최초 1회, 약 2~3분)
make compile SIM=iverilog

# ISA_VECTOR 케이스 빌드 + 실행
make runcase CASE=ISA_VECTOR SIM=iverilog

# 결과 확인
cat ./work/run_case.report    # → TEST PASS / TEST FAIL
```

> **참고**: iverilog 시뮬레이션은 512K×128bit SRAM 초기화로 인해
> 처음 실행 시 10~20분이 소요될 수 있습니다.

### 3. QEMU vs RTL 비교 (compare.sh)

```bash
cd smart_run
./compare.sh          # 양쪽 모두 실행 후 비교
./compare.sh qemu     # QEMU만 실행
./compare.sh rtl      # RTL만 실행

# 성공 시 출력:
# QEMU : PASS
# RTL  : PASS
# >>> BOTH PASS — firmware verified on QEMU and RTL <<<
```

---

## 아키텍처 요약

| 구분 | 컴파일 타깃 | 실행 환경 | 결과 확인 |
|------|------------|---------|---------|
| **QEMU** | rv64imafdcv, lp64d | qemu-riscv64 (Linux user-mode) | stdout (printf) |
| **RTL** | rv64imafdcv, lp64d | iverilog + C906 RTL | `run_case.report` + UART(0x10015000) |

---

## 구현 시 해결한 기술 이슈

### 1. `mxstatus` CSR — GCC 13 인식 불가

- **원인**: `mxstatus`는 T-Head 전용 CSR로, 표준 GCC 13이 이름을 모름
- **수정**: `crt0_v.s`에서 CSR 번호 직접 사용

```asm
# 변경 전 (원본 crt0.s — T-Head 전용 툴체인 필요)
csrs mxstatus, x3

# 변경 후 (crt0_v.s — GCC 13 호환)
csrs 0x7c0, x3
```

### 2. `vsetvli` vtypei 인코딩 불일치

- **원인**: RVV 버전에 따라 `vtypei` 비트 레이아웃이 다름

| | vlmul | vsew | e32+m1 vtypei |
|---|---|---|---|
| RVV 0.7.x (C906) | bits[4:3] | bits[2:0] | **0x02** |
| RVV 1.0 (GCC 13) | bits[2:0] | bits[5:3] | **0x10** |

- **수정**: `rvv_vadd_smoke.s`에서 `.word`로 C906 인코딩 직접 삽입

```asm
# GCC 13이 생성하는 인코딩 (vtypei=0x10) — C906에서 오동작
vsetvli t1, t0, e32, m1, tu, mu

# C906 RVV 0.7.x 호환 인코딩 (vtypei=0x02) — .word로 직접 지정
.word 0x0022F357    # vsetvli t1, t0, e32  (C906 v0.7.x)
```

### 3. vector_table `.long` vs `ld` 불일치

- **원인**: 예외 핸들러가 `ld`(8바이트 로드)를 사용하는데 vector_table 엔트리는 `.long`(4바이트)
  → 주소 계산 오류 → 무한 예외 루프 → 시뮬레이션 무한 대기
- **수정**: `crt0_v.s`에서 `.long` → `.dword`

```asm
# 변경 전
.long __fail     # 4바이트 엔트리 — ld로 읽으면 인접 엔트리까지 포함

# 변경 후
.dword __fail    # 8바이트 엔트리 — ld와 정확히 일치
```

### 4. rv64imafdcv multilib 없음 → `-lc` 링크 실패

- **원인**: `riscv64-unknown-elf-gcc 13.2`에 rv64v multilib 없음
- **수정**: ISA_VECTOR_build 규칙에서 `-nostartfiles` → `-nostdlib`으로 변경
  (어셈블리 테스트는 libc 불필요)

### 5. crt0의 `.ifdef C906FDV` 블록

- **원인**: `vsetvli x0, x0, e128` — RVV 1.0에서 유효하지 않은 SEW
- **수정**: `crt0_v.s`에서 해당 블록 제거 (벡터 레지스터 초기화는 선택적)

---

## QEMU 실행 참고

QEMU의 VLEN=128bit (기본값)이므로 한번에 4개(e32)만 처리됩니다.
`rvv_vadd.c`는 vsetvl 루프로 VLEN에 무관하게 동작합니다.

```c
// VLEN에 상관없이 동작하는 vsetvl 루프
for (int i = 0; i < N; ) {
    size_t vl = __riscv_vsetvl_e32m1(N - i);   // VLMAX까지 요청
    vint32m1_t v0 = __riscv_vle32_v_i32m1(arr_a + i, vl);
    vint32m1_t v1 = __riscv_vle32_v_i32m1(arr_b + i, vl);
    vint32m1_t v2 = __riscv_vadd_vv_i32m1(v0, v1, vl);
    __riscv_vse32_v_i32m1(arr_c + i, v2, vl);
    i += (int)vl;
}
```

---

## RTL pass/fail 메커니즘 (tb.v)

```
__exit  → x3 = 0x444333222   → testbench: TEST PASS
__fail  → x3 = 0x2382348720  → testbench: TEST FAIL
UART    → sw char, 0(t0) (t0=0x10015000) → 콘솔 출력
```
