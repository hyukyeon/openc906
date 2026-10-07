#!/bin/bash
#============================================================================
# Phase 3: CPU Pipeline Back-End (IU, RTU) - Lab Scripts
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
    echo -e "${BOLD}Phase 3 Lab Scripts - Pipeline Back-End${NC}"
    echo ""
    echo "Usage: $0 <lab_number>"
    echo ""
    echo "  lab1   ALU 동작 추적 (ISA_INT)"
    echo "  lab2   곱셈기/나눗셈기 관찰"
    echo "  lab3   Retire & IPC 분석"
    echo "  lab4   Branch Misprediction 관찰"
    echo "  lab5   IU/RTU RTL 소스 탐색"
    echo "  view   파형 열기"
    echo "  all    모든 Lab 순차 실행"
    echo ""
}

#--- Lab 1: ALU 동작 ---
lab1() {
    header "Lab 3.1: ALU Operation Tracing"
    info "Running ISA_INT to trace ALU operations..."
    echo ""

    make runcase CASE=ISA_INT SIM=iverilog DUMP=on

    echo ""
    info "=== ALU Observation Guide ==="
    echo ""
    echo "  IU hierarchy path:"
    echo "    tb.x_soc.x_cpu_sub_system_axi.x_c906_wrapper"
    echo "      .x_cpu_top.x_aq_top_0.x_aq_core.x_aq_iu_top"
    echo ""
    echo "  Key signals:"
    echo "    x_aq_iu_alu:"
    echo "      - alu_src0 / alu_src1    (operands)"
    echo "      - alu_result             (output)"
    echo "      - alu_op                 (operation type)"
    echo ""
    echo "  Exercises:"
    echo "    1. Find an ADD instruction: verify src0 + src1 = result"
    echo "    2. Find a shift instruction: check shift amount"
    echo "    3. Find a compare (SLT): verify comparison result"
}

#--- Lab 2: MUL/DIV 관찰 ---
lab2() {
    header "Lab 3.2: Multiplier & Divider Observation"
    info "Running ISA_INT to observe MUL/DIV operations..."
    echo ""

    make runcase CASE=ISA_INT SIM=iverilog DUMP=on

    echo ""
    info "=== Multiplier (Booth Encoding) ==="
    echo ""
    echo "  Key files:"
    echo "    ${GEN_RTL}/iu/rtl/aq_iu_mul.v"
    echo "    ${GEN_RTL}/iu/rtl/booth_code_33_bit.v"
    echo "    ${GEN_RTL}/iu/rtl/multiplier_33x33_partial.v"
    echo ""
    echo "  Observe:"
    echo "    - MUL instruction latency (cycles from issue to result)"
    echo "    - Booth partial product generation"
    echo "    - Pipeline stall during MUL"
    echo ""
    info "=== Divider (Radix-2 SRT) ==="
    echo ""
    echo "  Key files:"
    echo "    ${GEN_RTL}/iu/rtl/aq_iu_div.v"
    echo "    ${GEN_RTL}/iu/rtl/aq_iu_div_shift2_kernel.v"
    echo ""
    echo "  Observe:"
    echo "    - DIV instruction latency (~32 cycles for 64-bit)"
    echo "    - Quotient bits generated per cycle"
    echo "    - Long pipeline stall during DIV"
    echo "    - Compare MUL latency vs DIV latency"
}

#--- Lab 3: Retire & IPC ---
lab3() {
    header "Lab 3.3: Retire & IPC Analysis"
    info "Running ISA_INT to analyze retirement and IPC..."
    echo ""

    make runcase CASE=ISA_INT SIM=iverilog DUMP=on

    echo ""
    info "=== Retire Signal Guide ==="
    echo ""
    echo "  RTU hierarchy path:"
    echo "    tb.x_soc.x_cpu_sub_system_axi.x_c906_wrapper"
    echo "      .x_cpu_top.x_aq_top_0.x_aq_core.x_aq_rtu_top"
    echo ""
    echo "  Key signals:"
    echo "    core0_pad_retire       - 1 when instruction retires this cycle"
    echo "    core0_pad_retire_pc    - PC of retired instruction"
    echo ""
    echo "  IPC Measurement:"
    echo "    1. In gtkwave, place marker at a stable region"
    echo "    2. Count retire=1 cycles in a window"
    echo "    3. IPC = retire_count / total_cycles"
    echo "    4. C906 theoretical max IPC = 1.0 (single-issue)"
    echo ""
    echo "  RTU sub-modules:"
    echo "    - aq_rtu_retire.v   : in-order commit logic"
    echo "    - aq_rtu_wb.v       : write-back to GPR"
    echo "    - aq_rtu_rbus.v     : result bus arbitration"
    echo "    - aq_rtu_int.v      : interrupt sampling at retire"
}

#--- Lab 4: Branch Misprediction ---
lab4() {
    header "Lab 3.4: Branch Misprediction Observation"
    info "Running ISA_INT to observe branch mispredictions..."
    echo ""

    make runcase CASE=ISA_INT SIM=iverilog DUMP=on

    echo ""
    info "=== Misprediction Recovery Guide ==="
    echo ""
    echo "  BJU (Branch Jump Unit) path:"
    echo "    ...x_aq_core.x_aq_iu_top.x_aq_iu_bju"
    echo ""
    echo "  Key signals:"
    echo "    - bju_branch_taken     (actual branch result)"
    echo "    - bju_mispred          (misprediction detected)"
    echo "    - rtu_flush / rtu_redirect  (pipeline flush)"
    echo ""
    echo "  Observation steps:"
    echo "    1. Find bju_mispred = 1 in waveform"
    echo "    2. Count cycles until next retire (= penalty)"
    echo "    3. Verify IFU receives redirect PC"
    echo "    4. Check BHT counter update after resolution"
    echo ""
    echo "  Expected penalty: ~3-4 cycles"
}

#--- Lab 5: RTL 소스 탐색 ---
lab5() {
    header "Lab 3.5: IU/RTU RTL Source Exploration"

    echo -e "${BOLD}[IU - Integer Unit] ${GEN_RTL}/iu/rtl/${NC}"
    echo "───────────────────────────────────────────"
    ls -1 "${GEN_RTL}/iu/rtl/"*.v 2>/dev/null | while read f; do
        NAME=$(basename "$f")
        LINES=$(wc -l < "$f")
        printf "  %-40s %5d lines\n" "$NAME" "$LINES"
    done

    echo ""
    echo -e "${BOLD}[RTU - Retire Unit] ${GEN_RTL}/rtu/rtl/${NC}"
    echo "───────────────────────────────────────────"
    ls -1 "${GEN_RTL}/rtu/rtl/"*.v 2>/dev/null | while read f; do
        NAME=$(basename "$f")
        LINES=$(wc -l < "$f")
        printf "  %-40s %5d lines\n" "$NAME" "$LINES"
    done

    echo ""
    info "=== Recommended Reading Order ==="
    echo ""
    echo "  IU:  aq_iu_top → aq_iu_alu → aq_iu_bju → aq_iu_mul → aq_iu_div"
    echo "  RTU: aq_rtu_top → aq_rtu_retire → aq_rtu_wb → aq_rtu_rbus → aq_rtu_int"
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
    all) lab1; lab2; lab3; lab4; lab5; header "All Phase 3 Labs Complete!" ;;
    *) usage ;;
esac
