# OpenC906 Build Environment Setup

## Environment Status

| Item | Status |
|------|--------|
| iverilog 12.0 | Installed, Compile OK |
| verilator 5.020 | Installed (available if needed) |
| riscv64-unknown-elf-gcc 13.2 | Installed |
| gtkwave | Installed (for waveform viewing) |
| `xuantie_core.vvp` | Generated (56MB) |

## Quick Start

### 1. Environment Setup

```bash
cd openc906/smart_run
source ./setup/setup.sh
```

### 2. RTL Compile (iverilog)

```bash
make compile SIM=iverilog
```

Successful compilation generates `./work/xuantie_core.vvp`.

### 3. Run Simulation

```bash
# Run a test case (e.g. ISA_INT)
make runcase CASE=ISA_INT SIM=iverilog

# Run with waveform dump
make runcase CASE=ISA_INT SIM=iverilog DUMP=on
```

### 4. View Waveform

```bash
gtkwave ./work/test.vcd
```

## Available Test Cases

| Case | Description |
|------|-------------|
| ISA_INT | Integer ISA smoke test |
| ISA_LS | Load/Store smoke test |
| ISA_FP | Floating-point smoke test |
| ISA_THEAD | T-Head ISA extension test |
| coremark | CoreMark benchmark |
| MMU | MMU basic test |
| interrupt | PLIC interrupt smoke test |
| exception | Exception test |
| debug | Debug pattern test |
| csr | CSR operation test |
| cache | I/D Cache operation test |

List all cases:

```bash
make showcase
```

## Known Issues

- The standard `riscv64-unknown-elf-gcc` (13.2) does not support T-Head custom ISA extension (`xtheadc`).
  Assembly test cases (`.s` files) may require modifying the `-march` option in `tests/lib/Makefile`.
  - Original: `-march=rv64imafdcxtheadc`
  - Workaround: `-march=rv64imafdc`
  - Note: T-Head custom instructions in test code will fail to assemble with this workaround.

## Directory Structure

```
openc906/
├── C906_RTL_FACTORY/
│   ├── gen_rtl/          # C906 RTL source (Verilog)
│   └── setup/            # CODE_BASE_PATH setup
├── smart_run/
│   ├── Makefile           # Main simulation script
│   ├── setup/
│   │   ├── setup.sh       # Bash environment setup
│   │   └── example_setup.csh
│   ├── logical/           # SoC demo & testbench
│   ├── tests/             # Test cases, linker, boot code
│   └── work/              # Working directory (build output)
└── doc/                   # User & integration manual
```
