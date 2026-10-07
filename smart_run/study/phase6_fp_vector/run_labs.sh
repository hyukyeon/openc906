#!/bin/bash
#============================================================================
# Phase 6: Floating-Point & Vector Extensions - Lab Scripts
#============================================================================
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SMART_RUN="$(cd "${SCRIPT_DIR}/../.." && pwd)"
WORK="${SMART_RUN}/work"
GEN_RTL="${SMART_RUN}/../C906_RTL_FACTORY/gen_rtl"

source "${SMART_RUN}/setup/setup.sh"
cd "${SMART_RUN}"

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; BOLD='\033[1m'; NC='\033[0m'

header() { echo -e "\n${CYAN}${BOLD}════════════════════════════════════════${NC}"; echo -e "${CYAN}${BOLD}  $1${NC}"; echo -e "${CYAN}${BOLD}════════════════════════════════════════${NC}\n"; }
info()   { echo -e "${GREEN}[INFO]${NC} $1"; }

usage() {
    echo -e "${BOLD}Phase 6 Lab Scripts - Floating-Point${NC}"
    echo ""
    echo "Usage: $0 <lab_number>"
    echo ""
    echo "  lab1   FP 명령어 실행 관찰 (ISA_FP)"
    echo "  lab2   FP Add/Sub/Compare 파이프라인"
    echo "  lab3   FP Multiply-Accumulate (FMA)"
    echo "  lab4   FP Divide/Sqrt (SRT)"
    echo "  lab5   FPU RTL 소스 탐색"
    echo "  view   파형 열기"
    echo "  all    모든 Lab 순차 실행"
    echo ""
}

#--- Lab 1: FP 명령어 실행 ---
lab1() {
    header "Lab 6.1: Floating-Point Instruction Execution"
    info "Running ISA_FP (FP smoke test)..."
    echo ""

    make runcase CASE=ISA_FP SIM=iverilog DUMP=on

    echo ""
    info "=== FP Execution Observation Guide ==="
    echo ""
    echo "  FPU hierarchy path:"
    echo "    ...x_aq_core.x_aq_falu_top     (FP Add/Sub/Compare/Convert)"
    echo "    ...x_aq_core.x_aq_vfmau_top    (FP Multiply-Accumulate)"
    echo "    ...x_aq_core.x_aq_fdsu_top     (FP Divide/Sqrt)"
    echo "    ...x_aq_core.x_aq_vidu_top     (FP Instruction Decode)"
    echo ""
    echo "  FP Register File:"
    echo "    ...x_aq_core.x_aq_vidu_top.x_aq_vidu_vid_gpr_fp"
    echo "    - f0~f31 (32 × 64-bit FP registers)"
    echo ""
    echo "  FP CSR (fcsr):"
    echo "    - frm [7:5]: rounding mode (RNE=000, RTZ=001, ...)"
    echo "    - fflags [4:0]: NV|DZ|OF|UF|NX"
    echo ""
    echo "  Watch for:"
    echo "    - FP register read/write"
    echo "    - fcsr.fflags changes (exception flags)"
    echo "    - FP instruction retirement"
}

#--- Lab 2: FP Add/Sub 파이프라인 ---
lab2() {
    header "Lab 6.2: FP Addition Pipeline (VFALU)"
    info "Analyzing FADD pipeline stages..."
    echo ""

    make runcase CASE=ISA_FP SIM=iverilog DUMP=on

    echo ""
    info "=== FADD Pipeline Stages ==="
    echo ""
    echo "  Stage 1: Special Case Check"
    echo "    File: aq_fadd_double_special.v"
    echo "    - NaN, Inf, Zero detection"
    echo "    - Inf + (-Inf) = NaN"
    echo ""
    echo "  Stage 2: Alignment Shift"
    echo "    File: aq_fadd_shift_sub_h_double.v"
    echo "    - Compare exponents"
    echo "    - Shift smaller mantissa right"
    echo "    - Example: 1.5×2^3 + 1.2×2^1 → align to 2^3"
    echo ""
    echo "  Stage 3: Mantissa Addition"
    echo "    File: aq_fadd_double_add.v"
    echo "    - Add/subtract aligned mantissas"
    echo "    - Leading zero detection for normalization"
    echo ""
    echo "  Stage 4: Normalization + Rounding"
    echo "    File: aq_fadd_double_round.v"
    echo "    - Normalize to 1.xxx × 2^n"
    echo "    - Apply rounding mode (RNE, RTZ, ...)"
    echo "    - Set fflags (NX, OF, UF)"
    echo ""
    echo "  Also observe:"
    echo "    - FCMP (FEQ, FLT, FLE) in aq_fspu_top.v"
    echo "    - FCVT (format conversion) in aq_fcnvt_top.v"
}

#--- Lab 3: FMA ---
lab3() {
    header "Lab 6.3: Fused Multiply-Accumulate (VFMAU)"
    info "Analyzing FMA operation..."
    echo ""

    make runcase CASE=ISA_FP SIM=iverilog DUMP=on

    echo ""
    info "=== FMA Pipeline ==="
    echo ""
    echo "  FMADD.D: rd = (rs1 × rs2) + rs3 (single rounding)"
    echo ""
    echo "  VFMAU hierarchy:"
    echo "    aq_vfmau_top"
    echo "    ├── aq_vfmau_ctrl.v         (control FSM)"
    echo "    ├── aq_vfmau_dp.v           (datapath)"
    echo "    ├── aq_vfmau_mult.v         (multiplier)"
    echo "    │   ├── aq_vfmau_mult_double.v"
    echo "    │   ├── booth_code_54_bit.v     (Booth encoder)"
    echo "    │   └── aq_vfmau_multiplier_53x27_partial.v"
    echo "    ├── aq_vfmau_frac_mult.v    (fraction multiply)"
    echo "    ├── aq_vfmau_lza_double.v   (Leading Zero Anticipator)"
    echo "    └── aq_vfmau_special_judge_double.v"
    echo ""
    echo "  Key concepts:"
    echo "    - 53-bit mantissa × 53-bit mantissa"
    echo "    - Radix-4 Booth: 54-bit → 27 partial products"
    echo "    - LZA predicts shift amount in parallel with add"
    echo "    - Single rounding (more precise than MUL then ADD)"
    echo ""
    echo "  Observe latency:"
    echo "    - FMUL: issue → result (multi-cycle)"
    echo "    - FMADD: issue → result (slightly longer than FMUL)"
}

#--- Lab 4: FP Divide/Sqrt ---
lab4() {
    header "Lab 6.4: FP Divide / Square Root (VFDSU)"
    info "Analyzing FDIV/FSQRT with SRT algorithm..."
    echo ""

    make runcase CASE=ISA_FP SIM=iverilog DUMP=on

    echo ""
    info "=== FDIV/FSQRT Pipeline ==="
    echo ""
    echo "  VFDSU hierarchy:"
    echo "    aq_fdsu_top"
    echo "    ├── aq_fdsu_prepare.v      (operand preparation)"
    echo "    ├── aq_fdsu_special.v      (NaN, Inf, ÷0 check)"
    echo "    ├── aq_fdsu_srt.v          (SRT iterative division)"
    echo "    ├── aq_fdsu_denorm_shift.v (denormalized handling)"
    echo "    ├── aq_fdsu_round.v        (rounding)"
    echo "    ├── aq_fdsu_right_shift.v  (shift logic)"
    echo "    ├── aq_fdsu_pack.v         (result assembly)"
    echo "    └── aq_fdsu_scalar_ctrl.v  (control FSM)"
    echo ""
    echo "  SRT Division Algorithm:"
    echo "    - Iterative: produces 1-2 quotient bits per cycle"
    echo "    - ~30+ cycles for double-precision"
    echo "    - Longest latency FP operation"
    echo ""
    echo "  Special cases to watch:"
    echo "    - 1.0 / 0.0 → +Inf (DZ flag)"
    echo "    - 0.0 / 0.0 → NaN (NV flag)"
    echo "    - sqrt(-1.0) → NaN (NV flag)"
    echo ""
    echo "  Observe:"
    echo "    - FDIV total cycle count (issue to retire)"
    echo "    - Pipeline stall during FDIV"
    echo "    - Compare FDIV latency vs FMUL latency"
}

#--- Lab 5: RTL 소스 탐색 ---
lab5() {
    header "Lab 6.5: FPU RTL Source Exploration"

    for UNIT in "vfalu:VFALU - FP Add/Sub/Compare/Convert" "vfmau:VFMAU - FP Multiply-Accumulate" "vfdsu:VFDSU - FP Divide/Sqrt" "vidu:VIDU - FP/Vector Decode" "vdsp:VDSP - Vector Processing"; do
        DIR=$(echo "$UNIT" | cut -d: -f1)
        LABEL=$(echo "$UNIT" | cut -d: -f2)
        echo -e "${BOLD}[${LABEL}] ${GEN_RTL}/${DIR}/rtl/${NC}"
        echo "───────────────────────────────────────────"
        for f in "${GEN_RTL}/${DIR}/rtl/"*.v; do
            [ -f "$f" ] || continue
            NAME=$(basename "$f")
            LINES=$(wc -l < "$f")
            printf "  %-50s %5d lines\n" "$NAME" "$LINES"
        done
        echo ""
    done

    TOTAL=$(find "${GEN_RTL}/vfalu" "${GEN_RTL}/vfmau" "${GEN_RTL}/vfdsu" "${GEN_RTL}/vidu" "${GEN_RTL}/vdsp" -name "*.v" | wc -l)
    info "Total FPU files: ${TOTAL}"
}

view() {
    if [ -f "${WORK}/test.vcd" ]; then
        gtkwave "${WORK}/test.vcd" &
        info "GTKWave PID: $!"
    else
        echo -e "${RED}[ERROR]${NC} No waveform. Run a lab first."
    fi
}

case "${1:-}" in
    lab1) lab1 ;; lab2) lab2 ;; lab3) lab3 ;; lab4) lab4 ;; lab5) lab5 ;;
    view) view ;;
    all) lab1; lab2; lab3; lab4; lab5; header "All Phase 6 Labs Complete!" ;;
    *) usage ;;
esac
