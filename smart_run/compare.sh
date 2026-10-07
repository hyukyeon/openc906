#!/bin/bash
# compare.sh — Run RVV vadd test on both QEMU and RTL, then compare results
#
# Usage:
#   ./compare.sh              (both QEMU + RTL)
#   ./compare.sh qemu         (QEMU only)
#   ./compare.sh rtl          (RTL only)

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
QEMU_DIR="$SCRIPT_DIR/qemu_tests"
RTL_DIR="$SCRIPT_DIR"

MODE="${1:-both}"

SEP="========================================"

run_qemu() {
    echo ""
    echo "$SEP"
    echo " [QEMU]  rv64v / qemu-riscv64"
    echo "$SEP"
    cd "$QEMU_DIR"
    make -s all
    QEMU_OUT=$(qemu-riscv64 build/rvv_vadd 2>&1)
    echo "$QEMU_OUT"
    QEMU_EXIT=$?
    cd "$SCRIPT_DIR"
    export QEMU_OUT QEMU_EXIT
}

run_rtl() {
    echo ""
    echo "$SEP"
    echo " [RTL]   rv64v / iverilog + C906"
    echo "$SEP"
    cd "$RTL_DIR"
    make runcase CASE=ISA_VECTOR SIM=iverilog 2>&1
    RTL_REPORT="$RTL_DIR/work/run_case.report"
    if [ -f "$RTL_REPORT" ]; then
        RTL_RESULT=$(cat "$RTL_REPORT")
    else
        RTL_RESULT="NO REPORT"
    fi
    export RTL_RESULT
}

compare() {
    echo ""
    echo "$SEP"
    echo " Result Summary"
    echo "$SEP"

    QEMU_PASS=0
    RTL_PASS=0

    echo "$QEMU_OUT"   | grep -q "RESULT: PASS" && QEMU_PASS=1 || true
    echo "$RTL_RESULT" | grep -q "TEST PASS"    && RTL_PASS=1  || true

    echo ""
    printf "  QEMU  : %s\n" "$([ $QEMU_PASS -eq 1 ] && echo 'PASS' || echo 'FAIL')"
    printf "  RTL   : %s\n" "$([ $RTL_PASS  -eq 1 ] && echo 'PASS' || echo 'FAIL')"
    echo ""

    if [ $QEMU_PASS -eq 1 ] && [ $RTL_PASS -eq 1 ]; then
        echo "  >>> BOTH PASS — firmware verified on QEMU and RTL <<<"
        exit 0
    else
        echo "  >>> MISMATCH or FAIL <<<"
        exit 1
    fi
}

case "$MODE" in
    qemu)
        run_qemu
        ;;
    rtl)
        RTL_RESULT=""
        QEMU_OUT="(skipped)"
        run_rtl
        echo "RTL report: $RTL_RESULT"
        ;;
    both)
        run_qemu
        run_rtl
        compare
        ;;
    *)
        echo "Usage: $0 [qemu|rtl|both]"
        exit 1
        ;;
esac
