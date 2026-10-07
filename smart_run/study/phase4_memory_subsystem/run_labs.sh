#!/bin/bash
#============================================================================
# Phase 4: Memory Subsystem (LSU, MMU, BIU) - Lab Scripts
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
    echo -e "${BOLD}Phase 4 Lab Scripts - Memory Subsystem${NC}"
    echo ""
    echo "Usage: $0 <lab_number>"
    echo ""
    echo "  lab1   Load/Store 동작 추적 (ISA_LS)"
    echo "  lab2   D-Cache Miss & Fill 관찰 (cache)"
    echo "  lab3   MMU / TLB 관찰 (MMU)"
    echo "  lab4   AXI Bus Transaction 관찰"
    echo "  lab5   LSU/MMU/BIU RTL 소스 탐색"
    echo "  view   파형 열기"
    echo "  all    모든 Lab 순차 실행"
    echo ""
}

#--- Lab 1: Load/Store ---
lab1() {
    header "Lab 4.1: Load/Store Operation Tracing"
    info "Running ISA_LS (Load/Store smoke test)..."
    echo ""

    make runcase CASE=ISA_LS SIM=iverilog DUMP=on

    echo ""
    info "=== Load/Store Observation Guide ==="
    echo ""
    echo "  LSU hierarchy path:"
    echo "    ...x_aq_core.x_aq_lsu_top"
    echo ""
    echo "  Load path:"
    echo "    1. aq_lsu_ag     - Address generation (rs1 + offset)"
    echo "    2. MMU (uTLB)    - Virtual → Physical translation"
    echo "    3. D-Cache       - Tag compare, data read"
    echo "    4. Data return   - Byte/half/word alignment + sign-extend"
    echo ""
    echo "  Store path:"
    echo "    1. aq_lsu_ag     - Address generation"
    echo "    2. aq_lsu_stb    - Store Buffer write"
    echo "    3. D-Cache       - Write on commit (after retire)"
    echo ""
    echo "  Store-to-Load Forwarding:"
    echo "    - SW x1, 0(x10) followed by LW x2, 0(x10)"
    echo "    - Look for STB forwarding signal (stb_hit)"
}

#--- Lab 2: D-Cache Miss ---
lab2() {
    header "Lab 4.2: D-Cache Miss & Fill Observation"
    info "Running cache test..."
    echo ""

    make runcase CASE=cache SIM=iverilog DUMP=on

    echo ""
    info "=== D-Cache Miss Handling Guide ==="
    echo ""
    echo "  D-Cache: 32KB, 2-way, 64B line, write-back"
    echo ""
    echo "  Cache Miss Flow:"
    echo "    1. Tag mismatch → cache miss"
    echo "    2. LFB (Load Fill Buffer) entry allocated"
    echo "    3. BIU issues AXI read burst (8 beats × 16B = 128B)"
    echo "    4. Data arrives → cache line fill"
    echo "    5. Load data extracted and returned to LSU"
    echo ""
    echo "  Cache Eviction Flow:"
    echo "    1. Replacement needed (LRU selects victim way)"
    echo "    2. If dirty → Victim Buffer (VB)"
    echo "    3. New line fills selected way"
    echo "    4. VB writes dirty line back via BIU"
    echo ""
    echo "  Key signals:"
    echo "    - dcache_hit / dcache_miss"
    echo "    - lfb_valid (fill buffer active)"
    echo "    - vb_valid (victim buffer active)"
    echo "    - biu_pad_araddr / arvalid (AXI read request)"
}

#--- Lab 3: MMU / TLB ---
lab3() {
    header "Lab 4.3: MMU / TLB Observation"
    info "Running MMU test..."
    echo ""

    make runcase CASE=MMU SIM=iverilog DUMP=on

    echo ""
    info "=== MMU Observation Guide ==="
    echo ""
    echo "  MMU hierarchy path:"
    echo "    ...x_aq_core.x_aq_mmu_top"
    echo ""
    echo "  TLB Hierarchy:"
    echo "    uTLB (L1) → jTLB (L2) → PTW (Page Table Walker)"
    echo ""
    echo "  Sv39 Address Translation:"
    echo "    VA[38:30] = VPN[2] → Level-2 page table"
    echo "    VA[29:21] = VPN[1] → Level-1 page table"
    echo "    VA[20:12] = VPN[0] → Level-0 page table"
    echo "    VA[11:0]  = Page offset (passthrough)"
    echo ""
    echo "  Key signals:"
    echo "    - utlb_hit / utlb_miss"
    echo "    - jtlb_hit / jtlb_miss"
    echo "    - ptw_active (hardware page table walk)"
    echo "    - ptw_level (current walk level: 2→1→0)"
    echo ""
    echo "  Page Fault:"
    echo "    - PTE.V=0 or permission violation"
    echo "    - mcause = 12 (inst page fault)"
    echo "    - mcause = 13 (load page fault)"
    echo "    - mcause = 15 (store page fault)"
}

#--- Lab 4: AXI Bus ---
lab4() {
    header "Lab 4.4: AXI Bus Transaction Observation"
    info "Running ISA_LS to observe AXI transactions..."
    echo ""

    make runcase CASE=ISA_LS SIM=iverilog DUMP=on

    echo ""
    info "=== AXI Transaction Guide ==="
    echo ""
    echo "  AXI signals at SoC top:"
    echo "    tb.x_soc.biu_pad_*"
    echo ""
    echo "  Read Transaction:"
    echo "    biu_pad_arvalid / biu_pad_arready   (address handshake)"
    echo "    biu_pad_araddr                       (read address)"
    echo "    biu_pad_arlen                        (burst length)"
    echo "    biu_pad_rvalid / biu_pad_rready      (data handshake)"
    echo "    biu_pad_rdata                        (read data 128-bit)"
    echo "    biu_pad_rlast                        (last beat)"
    echo ""
    echo "  Write Transaction:"
    echo "    biu_pad_awvalid / awaddr / awlen    (write address)"
    echo "    biu_pad_wvalid / wdata / wstrb      (write data)"
    echo "    biu_pad_wlast                       (last beat)"
    echo "    biu_pad_bvalid                      (write response)"
    echo ""
    echo "  BIU Arbitration:"
    echo "    - D-Cache writeback > D-Cache read > I-Cache read"
}

#--- Lab 5: RTL 소스 탐색 ---
lab5() {
    header "Lab 4.5: LSU/MMU/BIU RTL Source Exploration"

    for UNIT in "lsu:LSU - Load/Store Unit" "mmu:MMU - Memory Management" "biu:BIU - Bus Interface"; do
        DIR=$(echo "$UNIT" | cut -d: -f1)
        LABEL=$(echo "$UNIT" | cut -d: -f2)
        echo -e "${BOLD}[${LABEL}] ${GEN_RTL}/${DIR}/rtl/${NC}"
        echo "───────────────────────────────────────────"
        ls -1 "${GEN_RTL}/${DIR}/rtl/"*.v 2>/dev/null | while read f; do
            NAME=$(basename "$f")
            LINES=$(wc -l < "$f")
            printf "  %-45s %5d lines\n" "$NAME" "$LINES"
        done
        echo ""
    done

    info "Total LSU files: $(ls -1 "${GEN_RTL}/lsu/rtl/"*.v | wc -l) (largest subsystem)"
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
    all) lab1; lab2; lab3; lab4; lab5; header "All Phase 4 Labs Complete!" ;;
    *) usage ;;
esac
