#!/bin/bash
# Environment setup for OpenC906 simulation (bash version)
# Usage: source ./setup/setup.sh

# Set CODE_BASE_PATH (points to C906_RTL_FACTORY)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export CODE_BASE_PATH="$(cd "${SCRIPT_DIR}/../../C906_RTL_FACTORY" && pwd)"
echo "Root of code base (CODE_BASE_PATH):"
echo "    ${CODE_BASE_PATH}"

# Set RISC-V toolchain path
export TOOL_EXTENSION="$(dirname "$(which riscv64-unknown-elf-gcc)")"
echo "Toolchain path (TOOL_EXTENSION):"
echo "    ${TOOL_EXTENSION}"

# Create work directory if needed
mkdir -p "${SCRIPT_DIR}/../work"
