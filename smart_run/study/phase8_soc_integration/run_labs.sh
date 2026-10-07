#!/bin/bash
#============================================================================
# Phase 8: SoC Integration & Advanced Topics - Lab Scripts
#============================================================================
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SMART_RUN="$(cd "${SCRIPT_DIR}/../.." && pwd)"
WORK="${SMART_RUN}/work"
GEN_RTL="${SMART_RUN}/../C906_RTL_FACTORY/gen_rtl"
TESTS="${SMART_RUN}/tests"

source "${SMART_RUN}/setup/setup.sh"
cd "${SMART_RUN}"

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; BOLD='\033[1m'; NC='\033[0m'

header() { echo -e "\n${CYAN}${BOLD}════════════════════════════════════════${NC}"; echo -e "${CYAN}${BOLD}  $1${NC}"; echo -e "${CYAN}${BOLD}════════════════════════════════════════${NC}\n"; }
info()   { echo -e "${GREEN}[INFO]${NC} $1"; }
warn()   { echo -e "${YELLOW}[NOTE]${NC} $1"; }

usage() {
    echo -e "${BOLD}Phase 8 Lab Scripts - SoC Integration & Advanced${NC}"
    echo ""
    echo "Usage: $0 <lab_number>"
    echo ""
    echo "  lab1   AXI Bus Transaction 추적"
    echo "  lab2   커스텀 어셈블리 테스트 작성 & 실행"
    echo "  lab3   SoC Peripheral (UART/GPIO) 관찰"
    echo "  lab4   전체 Regression 실행"
    echo "  lab5   SoC RTL 소스 탐색"
    echo "  view   파형 열기"
    echo "  all    모든 Lab 순차 실행 (lab4 제외)"
    echo ""
}

#--- Lab 1: AXI Bus ---
lab1() {
    header "Lab 8.1: AXI Bus Transaction Tracing"
    info "Running ISA_LS with dump to trace AXI..."
    echo ""

    make runcase CASE=ISA_LS SIM=iverilog DUMP=on

    echo ""
    info "=== AXI Bus Signals at SoC Top ==="
    echo ""
    echo "  Read Transaction (cache miss → memory read):"
    echo "    tb.x_soc.biu_pad_arvalid   (address valid)"
    echo "    tb.x_soc.biu_pad_arready   (slave ready)"
    echo "    tb.x_soc.biu_pad_araddr    (read address)"
    echo "    tb.x_soc.biu_pad_arlen     (burst length)"
    echo "    tb.x_soc.biu_pad_rvalid    (data valid)"
    echo "    tb.x_soc.biu_pad_rdata     (128-bit data)"
    echo "    tb.x_soc.biu_pad_rlast     (last beat)"
    echo ""
    echo "  Write Transaction (cache eviction → memory write):"
    echo "    tb.x_soc.biu_pad_awvalid / awaddr / awlen"
    echo "    tb.x_soc.biu_pad_wvalid / wdata / wstrb / wlast"
    echo "    tb.x_soc.biu_pad_bvalid    (write response)"
    echo ""
    echo "  Bus hierarchy:"
    echo "    AXI (128-bit) → AXI Interconnect → SRAM / CLINT"
    echo "                  → AXI→AHB bridge → AHB→APB → UART/GPIO/PLIC"
    echo ""
    echo "  Exercise:"
    echo "    1. Find a cache miss (arvalid goes high)"
    echo "    2. Count burst beats (arlen+1 beats)"
    echo "    3. Measure read latency (arvalid → rlast)"
}

#--- Lab 2: 커스텀 테스트 ---
lab2() {
    header "Lab 8.2: Custom Assembly Test Case"

    CUSTOM_DIR="${TESTS}/cases/custom"
    mkdir -p "${CUSTOM_DIR}"

    # 커스텀 테스트 작성
    cat > "${CUSTOM_DIR}/my_custom_test.s" << 'TESTEOF'
#============================================================================
# Custom Test: Basic Integer & Memory Operations
# Tests: ADD, SUB, AND, OR, XOR, SLL, SRL, LW, SW, BEQ, BNE
#============================================================================
.section .text
.globl _start

_start:
    #--- Test 1: ADD ---
    li      x1, 100
    li      x2, 200
    add     x3, x1, x2         # x3 = 300
    li      x4, 300
    bne     x3, x4, _fail

    #--- Test 2: SUB ---
    sub     x5, x2, x1         # x5 = 100
    li      x6, 100
    bne     x5, x6, _fail

    #--- Test 3: Logic ---
    li      x7, 0xFF00
    li      x8, 0x0FF0
    and     x9, x7, x8         # x9 = 0x0F00
    li      x10, 0x0F00
    bne     x9, x10, _fail

    or      x11, x7, x8        # x11 = 0xFFF0
    li      x12, 0xFFF0
    bne     x11, x12, _fail

    xor     x13, x7, x8        # x13 = 0xF0F0
    li      x14, 0xF0F0
    bne     x13, x14, _fail

    #--- Test 4: Shift ---
    li      x15, 1
    slli    x16, x15, 10       # x16 = 1024
    li      x17, 1024
    bne     x16, x17, _fail

    srli    x18, x16, 5        # x18 = 32
    li      x19, 32
    bne     x18, x19, _fail

    #--- Test 5: Memory ---
    la      x20, _test_data
    li      x21, 0xDEADBEEF
    sw      x21, 0(x20)        # store
    lw      x22, 0(x20)        # load back
    bne     x22, x21, _fail

    li      x23, 0x12345678
    sw      x23, 4(x20)        # store at offset 4
    lw      x24, 4(x20)        # load back
    bne     x24, x23, _fail

    #--- Test 6: Branch ---
    li      x25, 42
    li      x26, 42
    bne     x25, x26, _fail    # should not branch
    beq     x25, x26, _pass    # should branch to pass

_fail:
    li      x1, 0x2382348720   # FAIL magic value
    nop
    j       _fail

_pass:
    li      x1, 0x444333222    # PASS magic value
    nop
    j       _pass

.section .data
.align 4
_test_data:
    .word 0
    .word 0
    .word 0
    .word 0
TESTEOF

    info "Custom test written to: ${CUSTOM_DIR}/my_custom_test.s"

    # smart_cfg.mk에 custom 케이스가 없으면 추가
    if ! grep -q "custom_build:" "${SMART_RUN}/setup/smart_cfg.mk"; then
        cat >> "${SMART_RUN}/setup/smart_cfg.mk" << 'CFGEOF'

custom_build:
	@cp ./tests/cases/custom/* ./work
	@find ./tests/lib/ -maxdepth 1 -type f -exec cp {} ./work/ \;
	@cd ./work && make -s clean && make -s all CPU_ARCH_FLAG_0=c906fd ENDIAN_MODE=little-endian CASENAME=custom FILE=my_custom_test >& custom_build.case.log

CFGEOF
        # CASE_LIST에 custom 추가
        sed -i 's/^CASE_LIST := \\/CASE_LIST := \\\n      custom \\/' "${SMART_RUN}/setup/smart_cfg.mk"
        info "Added 'custom' to CASE_LIST in smart_cfg.mk"
    fi

    echo ""
    info "Building and running custom test..."
    echo ""

    make runcase CASE=custom SIM=iverilog DUMP=on

    echo ""
    if [ -f "${WORK}/run_case.report" ]; then
        RESULT=$(cat "${WORK}/run_case.report")
        if echo "$RESULT" | grep -q "TEST PASS"; then
            echo -e "  ${GREEN}${BOLD}CUSTOM TEST PASS!${NC}"
        else
            echo -e "  ${RED}${BOLD}CUSTOM TEST FAIL${NC}"
        fi
    fi

    echo ""
    info "Waveform: ${WORK}/test.vcd"
    info "Trace your instructions: retire_pc should show your code's addresses"
    info "Edit ${CUSTOM_DIR}/my_custom_test.s to add your own tests!"
}

#--- Lab 3: Peripheral 관찰 ---
lab3() {
    header "Lab 8.3: SoC Peripheral Observation"
    info "Running ISA_INT to observe UART output mechanism..."
    echo ""

    make runcase CASE=ISA_INT SIM=iverilog DUMP=on

    echo ""
    info "=== UART Console Output Mechanism ==="
    echo ""
    echo "  How printf works in simulation:"
    echo "    1. Test code calls printf/putchar"
    echo "    2. putchar writes byte to UART data register (0x10015000)"
    echo "    3. CPU executes: SW byte, 0(0x10015000)"
    echo "    4. tb.v detects write to 0x10015000:"
    echo "       - Checks biu_pad_awaddr == 0x10015000"
    echo "       - Extracts byte from biu_pad_wdata"
    echo "       - \$write(\"%c\", byte) to console"
    echo ""
    echo "  SoC Peripheral files:"
    echo "    ${SMART_RUN}/logical/uart/     (6 files)"
    echo "    ${SMART_RUN}/logical/gpio/     (3 files)"
    echo "    ${SMART_RUN}/logical/mem/      (4 files)"
    echo ""
    echo "  Bus bridge path:"
    echo "    CPU → AXI → axi2ahb.v → AHB → ahb2apb.v → APB → UART/GPIO"
    echo ""
    echo "  UART sub-modules:"
    echo "    uart.v         - top"
    echo "    uart_ctrl.v    - control logic"
    echo "    uart_apb_reg.v - APB register interface"
    echo "    uart_baud_gen.v - baud rate generator"
    echo "    uart_trans.v   - transmitter"
    echo "    uart_receive.v - receiver"
}

#--- Lab 4: Full Regression ---
lab4() {
    header "Lab 8.4: Full Regression Run"
    warn "This runs ALL test cases sequentially. May take a while."
    echo ""

    CASES=("ISA_INT" "ISA_LS" "ISA_FP" "csr" "exception" "interrupt" "cache" "MMU")
    PASS=0; FAIL=0; SKIP=0

    for CASE in "${CASES[@]}"; do
        echo -e -n "  Running ${YELLOW}${CASE}${NC}... "
        if make -s runcase CASE=${CASE} SIM=iverilog 2>&1 | tail -1 > /dev/null; then
            if [ -f "${WORK}/run_case.report" ] && grep -q "TEST PASS" "${WORK}/run_case.report"; then
                echo -e "${GREEN}PASS${NC}"
                ((PASS++))
            else
                echo -e "${RED}FAIL${NC}"
                ((FAIL++))
            fi
        else
            echo -e "${YELLOW}SKIP${NC}"
            ((SKIP++))
        fi
    done

    echo ""
    header "Regression Summary"
    echo -e "  ${GREEN}PASS${NC}: ${PASS}"
    echo -e "  ${RED}FAIL${NC}: ${FAIL}"
    echo -e "  ${YELLOW}SKIP${NC}: ${SKIP}"
    echo -e "  Total: $((PASS + FAIL + SKIP))"
    echo ""

    if [ "$FAIL" -eq 0 ] && [ "$SKIP" -eq 0 ]; then
        echo -e "  ${GREEN}${BOLD}All tests passed!${NC}"
    fi
}

#--- Lab 5: SoC RTL 소스 탐색 ---
lab5() {
    header "Lab 8.5: SoC RTL Source Exploration"

    echo -e "${BOLD}[SoC Testbench] ${SMART_RUN}/logical/${NC}"
    echo "───────────────────────────────────────────"
    for DIR in tb common axi ahb apb uart gpio mem bus clk; do
        if [ -d "${SMART_RUN}/logical/${DIR}" ]; then
            COUNT=$(ls -1 "${SMART_RUN}/logical/${DIR}/"*.v 2>/dev/null | wc -l)
            TOTAL_LINES=0
            for f in "${SMART_RUN}/logical/${DIR}/"*.v; do
                [ -f "$f" ] && TOTAL_LINES=$((TOTAL_LINES + $(wc -l < "$f")))
            done
            printf "  %-20s %2d files  %5d lines\n" "${DIR}/" "$COUNT" "$TOTAL_LINES"
        fi
    done

    echo ""
    echo -e "${BOLD}[CPU Top-Level] ${GEN_RTL}/cpu/rtl/${NC}"
    echo "───────────────────────────────────────────"
    for f in "${GEN_RTL}/cpu/rtl/"*.v; do
        [ -f "$f" ] || continue
        printf "  %-40s %5d lines\n" "$(basename "$f")" "$(wc -l < "$f")"
    done

    echo ""
    info "=== Module Hierarchy ==="
    echo "  tb → soc → cpu_sub_system_axi → openC906 → aq_top → aq_core"
    echo "         ├── axi_interconnect128 (bus)"
    echo "         ├── axi_slave128 (SRAM)"
    echo "         ├── clint_top (timer)"
    echo "         ├── plic_top (interrupt)"
    echo "         ├── axi2ahb → ahb2apb → uart, gpio"
    echo "         └── tdt_dmi_top (debug)"
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
    all) lab1; lab2; lab3; lab5; header "All Phase 8 Labs Complete! (lab4 skipped - run separately)" ;;
    *) usage ;;
esac
