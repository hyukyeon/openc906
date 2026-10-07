#!/bin/bash
#============================================================================
# Phase 5: Privileged Architecture & System - Lab Scripts
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
    echo -e "${BOLD}Phase 5 Lab Scripts - Privileged Architecture${NC}"
    echo ""
    echo "Usage: $0 <lab_number>"
    echo ""
    echo "  lab1   CSR 동작 관찰 (csr 테스트)"
    echo "  lab2   Exception 처리 관찰 (exception 테스트)"
    echo "  lab3   Interrupt 처리 관찰 (interrupt 테스트)"
    echo "  lab4   CP0/CLINT/PLIC/PMP RTL 소스 탐색"
    echo "  view   파형 열기"
    echo "  all    모든 Lab 순차 실행"
    echo ""
}

#--- Lab 1: CSR 동작 ---
lab1() {
    header "Lab 5.1: CSR Operation Observation"
    info "Running CSR test..."
    echo ""

    make runcase CASE=csr SIM=iverilog DUMP=on

    echo ""
    info "=== CSR Observation Guide ==="
    echo ""
    echo "  CP0 hierarchy path:"
    echo "    ...x_aq_core.x_aq_cp0_top"
    echo ""
    echo "  CSR Read/Write:"
    echo "    - CSRRW x1, mstatus, x2   → read mstatus to x1, write x2 to mstatus"
    echo "    - CSRRS x1, mie, x2       → read mie, set bits from x2"
    echo "    - CSRRC x1, mip, x2       → read mip, clear bits from x2"
    echo ""
    echo "  Key CSRs to watch:"
    echo "    - mstatus (0x300): MIE, MPIE, MPP fields"
    echo "    - misa    (0x301): ISA extensions"
    echo "    - mtvec   (0x305): trap vector address"
    echo "    - mepc    (0x341): exception PC"
    echo "    - mcause  (0x342): trap cause"
    echo ""
    echo "  Source files:"
    echo "    - aq_cp0_regs.v      : CSR register file"
    echo "    - aq_cp0_trap_csr.v  : mtvec, mepc, mcause, mtval"
    echo "    - aq_cp0_info_csr.v  : misa, mvendorid, marchid"
}

#--- Lab 2: Exception ---
lab2() {
    header "Lab 5.2: Exception Handling Observation"
    info "Running exception test..."
    echo ""

    make runcase CASE=exception SIM=iverilog DUMP=on

    echo ""
    info "=== Exception Handling Flow ==="
    echo ""
    echo "  Trap Entry (exception occurs):"
    echo "    1. mepc ← PC of faulting instruction"
    echo "    2. mcause ← exception code"
    echo "    3. mtval ← additional info (fault addr, etc.)"
    echo "    4. mstatus.MPIE ← mstatus.MIE"
    echo "    5. mstatus.MIE ← 0 (disable interrupts)"
    echo "    6. mstatus.MPP ← current privilege mode"
    echo "    7. PC ← mtvec (jump to handler)"
    echo ""
    echo "  Trap Return (MRET):"
    echo "    1. PC ← mepc"
    echo "    2. mstatus.MIE ← mstatus.MPIE"
    echo "    3. privilege ← mstatus.MPP"
    echo ""
    echo "  Signals to watch:"
    echo "    - retire_pc: observe PC jump to mtvec on exception"
    echo "    - mepc, mcause: verify correct values"
    echo "    - Pipeline flush on exception"
    echo ""
    echo "  Exception codes (mcause):"
    echo "     2 = Illegal instruction"
    echo "     3 = Breakpoint (EBREAK)"
    echo "     8 = ECALL from U-mode"
    echo "    11 = ECALL from M-mode"
    echo "    12 = Instruction page fault"
    echo "    13 = Load page fault"
}

#--- Lab 3: Interrupt ---
lab3() {
    header "Lab 5.3: Interrupt Handling Observation"
    info "Running interrupt (PLIC) test..."
    echo ""

    make runcase CASE=interrupt SIM=iverilog DUMP=on

    echo ""
    info "=== Interrupt Handling Guide ==="
    echo ""
    echo "  PLIC (Platform Level Interrupt Controller):"
    echo "    ...x_soc.x_plic_top"
    echo ""
    echo "  CLINT (Core Local Interrupt Timer):"
    echo "    ...x_soc.x_clint_top"
    echo ""
    echo "  Interrupt Flow:"
    echo "    1. External IRQ → PLIC priority arbitration"
    echo "    2. PLIC → CPU: machine external interrupt"
    echo "    3. mip.MEIP = 1 (interrupt pending)"
    echo "    4. If mstatus.MIE=1 && mie.MEIE=1:"
    echo "       → Trap to handler at mtvec"
    echo "    5. Handler reads PLIC claim register"
    echo "    6. Handler services interrupt"
    echo "    7. Handler writes PLIC complete register"
    echo "    8. MRET to return"
    echo ""
    echo "  Timer Interrupt:"
    echo "    - mtime counter (free-running)"
    echo "    - mtime >= mtimecmp → mip.MTIP = 1"
    echo "    - Handler updates mtimecmp for next interrupt"
    echo ""
    echo "  Key signals:"
    echo "    - mip register bits"
    echo "    - PLIC claim/complete"
    echo "    - mcause[63] = 1 for interrupt"
}

#--- Lab 4: RTL 소스 탐색 ---
lab4() {
    header "Lab 5.4: CP0/CLINT/PLIC/PMP RTL Source"

    for UNIT in "cp0:CP0 - System Control" "clint:CLINT - Timer" "plic:PLIC - Interrupt Controller" "pmp:PMP - Memory Protection"; do
        DIR=$(echo "$UNIT" | cut -d: -f1)
        LABEL=$(echo "$UNIT" | cut -d: -f2)
        echo -e "${BOLD}[${LABEL}] ${GEN_RTL}/${DIR}/rtl/${NC}"
        echo "───────────────────────────────────────────"
        for f in "${GEN_RTL}/${DIR}/rtl/"*.v; do
            [ -f "$f" ] || continue
            NAME=$(basename "$f")
            LINES=$(wc -l < "$f")
            printf "  %-45s %5d lines\n" "$NAME" "$LINES"
        done
        echo ""
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
    lab1) lab1 ;; lab2) lab2 ;; lab3) lab3 ;; lab4) lab4 ;;
    view) view ;;
    all) lab1; lab2; lab3; lab4; header "All Phase 5 Labs Complete!" ;;
    *) usage ;;
esac
