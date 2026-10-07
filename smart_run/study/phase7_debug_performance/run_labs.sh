#!/bin/bash
#============================================================================
# Phase 7: Debug & Performance Monitoring - Lab Scripts
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
    echo -e "${BOLD}Phase 7 Lab Scripts - Debug & Performance${NC}"
    echo ""
    echo "Usage: $0 <lab_number>"
    echo ""
    echo "  lab1   JTAG Debug 동작 관찰 (debug 테스트)"
    echo "  lab2   Hardware Breakpoint 분석"
    echo "  lab3   Performance Counter 관찰"
    echo "  lab4   IPC 비교 분석 (ISA_INT vs coremark)"
    echo "  lab5   DTU/TDT/PMU RTL 소스 탐색"
    echo "  view   파형 열기"
    echo "  all    모든 Lab 순차 실행 (lab4 제외 - 오래 걸림)"
    echo ""
}

#--- Lab 1: JTAG Debug ---
lab1() {
    header "Lab 7.1: JTAG Debug Operation"
    info "Running debug test (includes JTAG driver)..."
    echo ""

    make runcase CASE=debug SIM=iverilog DUMP=on

    echo ""
    info "=== Debug Infrastructure ==="
    echo ""
    echo "  Debug signal hierarchy:"
    echo "    tb.jclk                          (JTAG clock, 40ns period)"
    echo "    tb.jrst_b                        (JTAG reset)"
    echo "    tb.jtg_tms / jtg_tdi / jtg_tdo  (JTAG data)"
    echo ""
    echo "  Debug chain:"
    echo "    JTAG TAP → DTM → DMI → DM → DTU → CPU"
    echo ""
    echo "  DTM (Debug Transport Module):"
    echo "    ...x_soc.x_tdt_dmi_top.x_tdt_dtm_top"
    echo "    - JTAG state machine (IR scan, DR scan)"
    echo "    - dtmcs register access"
    echo ""
    echo "  DM (Debug Module):"
    echo "    ...x_soc.x_tdt_dmi_top.x_tdt_dm_top"
    echo "    - dmcontrol (halt/resume request)"
    echo "    - dmstatus  (halted/running status)"
    echo "    - Abstract commands (register R/W)"
    echo ""
    echo "  DTU (CPU-side Debug Unit):"
    echo "    ...x_aq_core.x_aq_dtu_top"
    echo "    - Halt/resume control"
    echo "    - Trigger (hardware breakpoint)"
    echo "    - dcsr, dpc registers"
}

#--- Lab 2: Hardware Breakpoint ---
lab2() {
    header "Lab 7.2: Hardware Breakpoint Analysis"
    info "Analyzing breakpoint mechanism in debug test..."
    echo ""

    make runcase CASE=debug SIM=iverilog DUMP=on

    echo ""
    info "=== Hardware Breakpoint Guide ==="
    echo ""
    echo "  Trigger module:"
    echo "    ...x_aq_dtu_top.x_aq_dtu_trigger_module"
    echo "    ...x_aq_dtu_top.x_aq_dtu_mcontrol"
    echo ""
    echo "  Breakpoint setup:"
    echo "    1. Write tdata1 (mcontrol): type, action, execute bit"
    echo "    2. Write tdata2: match address (breakpoint PC)"
    echo "    3. CPU execution reaches tdata2 address"
    echo "    4. Trigger fires → enter Debug Mode"
    echo ""
    echo "  Key signals:"
    echo "    - tdata1, tdata2 register values"
    echo "    - trigger_match / trigger_hit"
    echo "    - debug_mode_enter"
    echo "    - dpc (debug PC - where CPU was halted)"
    echo ""
    echo "  Single Step:"
    echo "    - dcsr.step = 1"
    echo "    - Resume → execute 1 instruction → halt again"
    echo "    - dpc advances by 1 instruction"
    echo ""
    echo "  Clock Domain Crossing:"
    echo "    - TCK (~25MHz) ≠ CPU clock (~100MHz+)"
    echo "    - aq_dtu_cdc.v handles synchronization"
    echo "    - Level sync: aq_dtu_cdc_lvl.v"
    echo "    - Pulse sync: aq_dtu_cdc_pulse.v"
}

#--- Lab 3: Performance Counter ---
lab3() {
    header "Lab 7.3: Performance Counter Observation"
    info "Running ISA_INT to observe performance counters..."
    echo ""

    make runcase CASE=ISA_INT SIM=iverilog DUMP=on

    echo ""
    info "=== Performance Monitoring Unit (PMU) ==="
    echo ""
    echo "  PMU hierarchy:"
    echo "    ...x_aq_core.x_aq_hpcp_top"
    echo ""
    echo "  Fixed counters:"
    echo "    mcycle   (0xB00): clock cycles (increments every cycle)"
    echo "    minstret (0xB02): retired instructions"
    echo ""
    echo "  Configurable counters:"
    echo "    mhpmcounter3~31: programmable event counters"
    echo "    mhpmevent3~31:   event selector registers"
    echo ""
    echo "  Possible events:"
    echo "    - I-Cache miss"
    echo "    - D-Cache miss"
    echo "    - Branch misprediction"
    echo "    - TLB miss"
    echo "    - Pipeline stall cycles"
    echo ""
    echo "  Key files:"
    echo "    - aq_hpcp_top.v           : PMU top-level"
    echo "    - aq_hpcp_cnt.v           : counter logic"
    echo "    - aq_hpcp_event.v         : event selection"
    echo "    - aq_hpcp_adder_sel.v     : multi-event counting"
    echo "    - aq_hpcp_cntof_reg.v     : overflow detection"
    echo "    - aq_hpcp_cntinten_reg.v  : overflow interrupt enable"
    echo ""
    echo "  IPC from counters:"
    echo "    IPC = minstret / mcycle"
}

#--- Lab 4: IPC 비교 ---
lab4() {
    header "Lab 7.4: IPC Comparison Analysis"
    info "Running ISA_INT and measuring execution..."
    echo ""

    echo -e "${YELLOW}--- ISA_INT ---${NC}"
    START=$(date +%s%N)
    make -s runcase CASE=ISA_INT SIM=iverilog 2>&1 | tail -3
    END=$(date +%s%N)
    INT_TIME=$(( (END - START) / 1000000 ))

    RESULT_INT="UNKNOWN"
    [ -f "${WORK}/run_case.report" ] && RESULT_INT=$(cat "${WORK}/run_case.report")

    echo ""
    echo -e "${YELLOW}--- ISA_LS ---${NC}"
    START=$(date +%s%N)
    make -s runcase CASE=ISA_LS SIM=iverilog 2>&1 | tail -3
    END=$(date +%s%N)
    LS_TIME=$(( (END - START) / 1000000 ))

    RESULT_LS="UNKNOWN"
    [ -f "${WORK}/run_case.report" ] && RESULT_LS=$(cat "${WORK}/run_case.report")

    echo ""
    echo -e "${YELLOW}--- ISA_FP ---${NC}"
    START=$(date +%s%N)
    make -s runcase CASE=ISA_FP SIM=iverilog 2>&1 | tail -3
    END=$(date +%s%N)
    FP_TIME=$(( (END - START) / 1000000 ))

    RESULT_FP="UNKNOWN"
    [ -f "${WORK}/run_case.report" ] && RESULT_FP=$(cat "${WORK}/run_case.report")

    echo ""
    header "Execution Time Comparison"
    printf "  %-15s %8s ms   %s\n" "ISA_INT" "$INT_TIME" "$RESULT_INT"
    printf "  %-15s %8s ms   %s\n" "ISA_LS" "$LS_TIME" "$RESULT_LS"
    printf "  %-15s %8s ms   %s\n" "ISA_FP" "$FP_TIME" "$RESULT_FP"
    echo ""
    info "For deeper IPC analysis, run with DUMP=on and"
    info "count retire signals in gtkwave waveform."
    echo ""
    info "Note: coremark takes very long in iverilog simulation."
    info "To run: make runcase CASE=coremark SIM=iverilog"
}

#--- Lab 5: RTL 소스 탐색 ---
lab5() {
    header "Lab 7.5: DTU/TDT/PMU RTL Source"

    echo -e "${BOLD}[DTU - Debug Transfer Unit] ${GEN_RTL}/dtu/rtl/${NC}"
    echo "───────────────────────────────────────────"
    for f in "${GEN_RTL}/dtu/rtl/"*.v; do
        [ -f "$f" ] || continue
        printf "  %-45s %5d lines\n" "$(basename "$f")" "$(wc -l < "$f")"
    done

    echo ""
    echo -e "${BOLD}[TDT - RISC-V Debug Transport] ${GEN_RTL}/tdt/rtl/${NC}"
    echo "───────────────────────────────────────────"
    find "${GEN_RTL}/tdt/rtl" -name "*.v" -o -name "*.h" | sort | while read f; do
        REL=$(echo "$f" | sed "s|${GEN_RTL}/tdt/rtl/||")
        LINES=$(wc -l < "$f")
        printf "  %-45s %5d lines\n" "$REL" "$LINES"
    done

    echo ""
    echo -e "${BOLD}[PMU - Performance Monitoring] ${GEN_RTL}/pmu/rtl/${NC}"
    echo "───────────────────────────────────────────"
    for f in "${GEN_RTL}/pmu/rtl/"*.v; do
        [ -f "$f" ] || continue
        printf "  %-45s %5d lines\n" "$(basename "$f")" "$(wc -l < "$f")"
    done
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
    all) lab1; lab2; lab3; lab5; header "All Phase 7 Labs Complete! (lab4 skipped - run separately)" ;;
    *) usage ;;
esac
