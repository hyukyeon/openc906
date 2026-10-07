#!/bin/bash
#============================================================================
# Phase 1: Project Orientation & Simulation Basics - Lab Scripts
#============================================================================
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SMART_RUN="$(cd "${SCRIPT_DIR}/../.." && pwd)"
WORK="${SMART_RUN}/work"

# 환경 설정
source "${SMART_RUN}/setup/setup.sh"
cd "${SMART_RUN}"

# 색상 정의
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; BOLD='\033[1m'; NC='\033[0m'

header() { echo -e "\n${CYAN}${BOLD}════════════════════════════════════════${NC}"; echo -e "${CYAN}${BOLD}  $1${NC}"; echo -e "${CYAN}${BOLD}════════════════════════════════════════${NC}\n"; }
info()   { echo -e "${GREEN}[INFO]${NC} $1"; }
warn()   { echo -e "${YELLOW}[NOTE]${NC} $1"; }

usage() {
    echo -e "${BOLD}Phase 1 Lab Scripts${NC}"
    echo ""
    echo "Usage: $0 <lab_number>"
    echo ""
    echo "  lab1   RTL 컴파일 (iverilog)"
    echo "  lab2   ISA_INT 테스트 실행 + 파형 덤프"
    echo "  lab3   파형 뷰어(gtkwave) 실행"
    echo "  lab4   전체 테스트 케이스 목록 확인"
    echo "  lab5   여러 테스트 케이스 순차 실행"
    echo "  all    모든 Lab 순차 실행 (gtkwave 제외)"
    echo ""
}

#--- Lab 1: RTL 컴파일 ---
lab1() {
    header "Lab 1.1: RTL Compile (iverilog)"
    info "Compiling OpenC906 RTL with iverilog..."
    info "Command: make compile SIM=iverilog"
    echo ""

    make compile SIM=iverilog

    if [ -f "${WORK}/xuantie_core.vvp" ]; then
        SIZE=$(du -h "${WORK}/xuantie_core.vvp" | cut -f1)
        echo ""
        info "Compilation successful!"
        info "Output: ${WORK}/xuantie_core.vvp (${SIZE})"
    else
        echo -e "${RED}[FAIL]${NC} Compilation failed. xuantie_core.vvp not found."
        exit 1
    fi
}

#--- Lab 2: ISA_INT 테스트 실행 ---
lab2() {
    header "Lab 1.2: Run ISA_INT Test with Waveform Dump"
    info "Running integer ISA smoke test..."
    info "Command: make runcase CASE=ISA_INT SIM=iverilog DUMP=on"
    echo ""

    make runcase CASE=ISA_INT SIM=iverilog DUMP=on

    echo ""
    info "=== Test Result ==="
    if [ -f "${WORK}/run_case.report" ]; then
        RESULT=$(cat "${WORK}/run_case.report")
        if echo "$RESULT" | grep -q "TEST PASS"; then
            echo -e "  ${GREEN}${BOLD}TEST PASS${NC}"
        else
            echo -e "  ${RED}${BOLD}TEST FAIL${NC}"
        fi
    fi

    if [ -f "${WORK}/test.vcd" ]; then
        VCD_SIZE=$(du -h "${WORK}/test.vcd" | cut -f1)
        info "Waveform: ${WORK}/test.vcd (${VCD_SIZE})"
        info "Run 'gtkwave ${WORK}/test.vcd' to view waveform"
    fi
}

#--- Lab 3: GTKWave 실행 ---
lab3() {
    header "Lab 1.3: Open Waveform in GTKWave"

    if [ ! -f "${WORK}/test.vcd" ]; then
        warn "No waveform file found. Running Lab 2 first..."
        lab2
    fi

    info "Opening GTKWave..."
    info "Key signals to add:"
    echo "  - tb.clk"
    echo "  - tb.rst_b"
    echo "  - tb.x_soc.x_cpu_sub_system_axi.x_c906_wrapper.x_cpu_top.core0_pad_retire"
    echo "  - tb.x_soc.x_cpu_sub_system_axi.x_c906_wrapper.x_cpu_top.core0_pad_retire_pc"
    echo ""

    if command -v gtkwave &>/dev/null; then
        gtkwave "${WORK}/test.vcd" &
        info "GTKWave launched in background (PID: $!)"
    else
        warn "gtkwave not found. Install with: sudo apt install gtkwave"
    fi
}

#--- Lab 4: 테스트 케이스 목록 ---
lab4() {
    header "Lab 1.4: Available Test Cases"
    info "Command: make showcase"
    echo ""
    make showcase
    echo ""
    info "Use 'make runcase CASE=<name> SIM=iverilog' to run any case"
}

#--- Lab 5: 여러 테스트 실행 ---
lab5() {
    header "Lab 1.5: Run Multiple Test Cases"

    CASES=("ISA_INT" "ISA_LS" "ISA_FP" "csr" "exception")
    PASS_COUNT=0
    FAIL_COUNT=0

    for CASE in "${CASES[@]}"; do
        echo -e "\n${YELLOW}--- Running: ${CASE} ---${NC}"
        make -s runcase CASE=${CASE} SIM=iverilog 2>&1 | tail -5

        if [ -f "${WORK}/run_case.report" ]; then
            RESULT=$(cat "${WORK}/run_case.report")
            if echo "$RESULT" | grep -q "TEST PASS"; then
                echo -e "  ${GREEN}PASS${NC}: ${CASE}"
                ((PASS_COUNT++))
            else
                echo -e "  ${RED}FAIL${NC}: ${CASE}"
                ((FAIL_COUNT++))
            fi
        fi
    done

    echo ""
    header "Summary"
    echo -e "  ${GREEN}PASS${NC}: ${PASS_COUNT}"
    echo -e "  ${RED}FAIL${NC}: ${FAIL_COUNT}"
    echo -e "  Total: $((PASS_COUNT + FAIL_COUNT))"
}

#--- Main ---
case "${1:-}" in
    lab1) lab1 ;;
    lab2) lab2 ;;
    lab3) lab3 ;;
    lab4) lab4 ;;
    lab5) lab5 ;;
    all)
        lab1
        lab2
        lab4
        lab5
        echo ""
        header "All Phase 1 Labs Complete!"
        ;;
    *) usage ;;
esac
