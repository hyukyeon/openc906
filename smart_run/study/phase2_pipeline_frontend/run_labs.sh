#!/bin/bash
#============================================================================
# Phase 2: CPU Pipeline Front-End (IFU, IDU) - Lab Scripts
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
    echo -e "${BOLD}Phase 2 Lab Scripts - Pipeline Front-End${NC}"
    echo ""
    echo "Usage: $0 <lab_number>"
    echo ""
    echo "  lab1   IFU 파형 관찰 (ISA_INT + DUMP)"
    echo "  lab2   Branch Prediction 분석 (분기 테스트)"
    echo "  lab3   IFU/IDU RTL 소스 구조 탐색"
    echo "  lab4   I-Cache 동작 관찰 (cache 테스트)"
    echo "  view   마지막 파형 열기 (gtkwave)"
    echo "  all    모든 Lab 순차 실행"
    echo ""
}

#--- Lab 1: IFU 파형 관찰 ---
lab1() {
    header "Lab 2.1: IFU Waveform Observation"
    info "Running ISA_INT with waveform dump to observe IFU signals..."
    info "Command: make runcase CASE=ISA_INT SIM=iverilog DUMP=on"
    echo ""

    make runcase CASE=ISA_INT SIM=iverilog DUMP=on

    echo ""
    info "=== Signals to observe in gtkwave ==="
    echo ""
    echo "  [PC Generation]"
    echo "    tb.x_soc...x_aq_ifu_top.x_aq_ifu_pcgen.*"
    echo ""
    echo "  [I-Cache]"
    echo "    tb.x_soc...x_aq_ifu_top.x_aq_ifu_icache.*"
    echo ""
    echo "  [Branch Prediction]"
    echo "    tb.x_soc...x_aq_ifu_top.x_aq_ifu_bht.*       (Branch History Table)"
    echo "    tb.x_soc...x_aq_ifu_top.x_aq_ifu_btb.*       (Branch Target Buffer)"
    echo "    tb.x_soc...x_aq_ifu_top.x_aq_ifu_ras.*       (Return Address Stack)"
    echo ""
    echo "  [Instruction Buffer]"
    echo "    tb.x_soc...x_aq_ifu_top.x_aq_ifu_ibuf.*"
    echo ""
    info "Run: $0 view  (to open gtkwave)"
}

#--- Lab 2: Branch Prediction 분석 ---
lab2() {
    header "Lab 2.2: Branch Prediction Analysis"
    info "Running ISA_INT to analyze branch prediction behavior..."
    echo ""

    make runcase CASE=ISA_INT SIM=iverilog DUMP=on

    echo ""
    info "=== Branch Prediction Analysis Guide ==="
    echo ""
    echo "  1. Open waveform: gtkwave ${WORK}/test.vcd"
    echo ""
    echo "  2. Find branch misprediction signals:"
    echo "     - IFU redirect (misprediction recovery)"
    echo "     - BJU (Branch Jump Unit) branch result"
    echo "     - Pipeline flush signals"
    echo ""
    echo "  3. Key observations:"
    echo "     - BHT 2-bit counter transitions (00↔01↔10↔11)"
    echo "     - BTB hit/miss on branch instructions"
    echo "     - RAS push (JAL/JALR) and pop (RET)"
    echo "     - Misprediction penalty (count flush cycles)"
    echo ""
    echo "  4. Search pattern in RTL source:"
    echo "     grep -n 'mispred\|flush\|redirect' ${GEN_RTL}/ifu/rtl/aq_ifu_*.v"
}

#--- Lab 3: RTL 소스 구조 탐색 ---
lab3() {
    header "Lab 2.3: IFU/IDU RTL Source Exploration"

    echo -e "${BOLD}[IFU - Instruction Fetch Unit] ${GEN_RTL}/ifu/rtl/${NC}"
    echo "───────────────────────────────────────────"
    ls -1 "${GEN_RTL}/ifu/rtl/"*.v 2>/dev/null | while read f; do
        NAME=$(basename "$f")
        LINES=$(wc -l < "$f")
        printf "  %-40s %5d lines\n" "$NAME" "$LINES"
    done

    echo ""
    echo -e "${BOLD}[IDU - Instruction Decode Unit] ${GEN_RTL}/idu/rtl/${NC}"
    echo "───────────────────────────────────────────"
    ls -1 "${GEN_RTL}/idu/rtl/"*.v 2>/dev/null | while read f; do
        NAME=$(basename "$f")
        LINES=$(wc -l < "$f")
        printf "  %-40s %5d lines\n" "$NAME" "$LINES"
    done

    echo ""
    info "=== Recommended Reading Order ==="
    echo ""
    echo "  IFU:"
    echo "    1. aq_ifu_top.v         - Top-level, port connections"
    echo "    2. aq_ifu_pcgen.v       - PC generation logic"
    echo "    3. aq_ifu_icache.v      - I-Cache controller"
    echo "    4. aq_ifu_bht.v         - Branch History Table"
    echo "    5. aq_ifu_btb.v         - Branch Target Buffer"
    echo "    6. aq_ifu_ibuf.v        - Instruction Buffer"
    echo ""
    echo "  IDU:"
    echo "    1. aq_idu_top.v         - Top-level"
    echo "    2. aq_idu_id_decd.v     - Main decoder (largest file)"
    echo "    3. aq_idu_id_gpr.v      - Register file"
    echo "    4. aq_idu_id_wbt.v      - Scoreboard (hazard detection)"
    echo "    5. aq_idu_expand_32.v   - Compressed instruction expansion"
}

#--- Lab 4: I-Cache 동작 관찰 ---
lab4() {
    header "Lab 2.4: I-Cache & Data Hazard Observation"
    info "Running cache test to observe I-Cache behavior..."
    echo ""

    make runcase CASE=cache SIM=iverilog DUMP=on

    echo ""
    info "=== I-Cache Observation Guide ==="
    echo ""
    echo "  I-Cache Structure:"
    echo "    - 32KB, 2-way set associative"
    echo "    - 64-byte cache line, 256 sets"
    echo "    - Tag array: aq_ifu_icache_tag_array"
    echo "    - Data array: aq_ifu_icache_data_array"
    echo ""
    echo "  Signals to watch:"
    echo "    - icache_hit / icache_miss"
    echo "    - tag comparison signals"
    echo "    - BIU request for cache line fill"
    echo ""
    echo "  Data Hazard (IDU WBT):"
    echo "    - WBT busy flags per register"
    echo "    - Pipeline stall when RAW detected"
    echo "    - Stall release after write-back"
}

#--- View waveform ---
view() {
    if [ -f "${WORK}/test.vcd" ]; then
        info "Opening gtkwave..."
        gtkwave "${WORK}/test.vcd" &
        info "GTKWave PID: $!"
    else
        echo -e "${RED}[ERROR]${NC} No waveform file. Run a lab first."
    fi
}

#--- Main ---
case "${1:-}" in
    lab1) lab1 ;;
    lab2) lab2 ;;
    lab3) lab3 ;;
    lab4) lab4 ;;
    view) view ;;
    all)  lab1; lab2; lab3; lab4; header "All Phase 2 Labs Complete!" ;;
    *) usage ;;
esac
