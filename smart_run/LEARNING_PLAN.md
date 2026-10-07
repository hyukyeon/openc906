# OpenC906 RISC-V CPU Core Learning Plan

## Overview

OpenC906 is a 64-bit RISC-V CPU core by T-Head (Alibaba).
253 Verilog files across 26 subsystems. This plan progressively builds understanding from
basic simulation to deep architectural analysis.

---

## Phase 1: Project Orientation & Simulation Basics (Week 1)

### 1.1 Documentation Reading
- [ ] `doc/openc906 datasheet.pdf` - Architecture overview, block diagram, feature list
- [ ] `doc/玄铁C906用户手册(openc906)_20240627.pdf` - User manual (detailed)
- [ ] `doc/玄铁C906集成手册(openc906)_20240627.pdf` - Integration manual

### 1.2 First Simulation Run
```bash
cd smart_run
source ./setup/setup.sh
make compile SIM=iverilog
make runcase CASE=ISA_INT SIM=iverilog
```
- [ ] Confirm `TEST PASS` in `work/run_case.report`
- [ ] Run with `DUMP=on`, open `work/test.vcd` in gtkwave
- [ ] Identify clock, reset, retire signals in waveform

### 1.3 Testbench Understanding
- [ ] Read `logical/tb/tb.v` - clock/reset generation, memory init, pass/fail detection
- [ ] Read `logical/common/soc.v` - SoC top-level interconnect
- [ ] Understand the simulation flow: `.s` -> `.elf` -> `.hex` -> `.pat` -> memory load -> simulate

### Key Questions to Answer
- How does the testbench detect PASS/FAIL? (magic value `64'h444333222`)
- How is the program loaded into memory? (`$readmemh`)
- What is the memory map? (inst @ 0x0, data @ 0x10000)

---

## Phase 2: CPU Pipeline Front-End (Week 2-3)

### 2.1 IFU (Instruction Fetch Unit) - 23 files
```
gen_rtl/ifu/rtl/
```
| Module | Focus |
|--------|-------|
| `aq_ifu_top.v` | Top-level connections |
| `aq_ifu_pcgen.v` | PC generation logic |
| `aq_ifu_icache.v` | I-Cache architecture (2-way set associative) |
| `aq_ifu_btb.v` | Branch Target Buffer |
| `aq_ifu_bht.v` | Branch History Table (2-bit saturating counter) |
| `aq_ifu_ras.v` | Return Address Stack |
| `aq_ifu_ibuf.v` | Instruction buffer (decoupling fetch/decode) |
| `aq_ifu_pre_decd.v` | Pre-decode for branch prediction |

#### Simulation Exercises
```bash
# Run integer test and observe IFU signals
make runcase CASE=ISA_INT SIM=iverilog DUMP=on
# In gtkwave, trace: tb.x_soc.x_cpu_sub_system_axi...x_aq_ifu_top
```
- [ ] Trace PC flow from reset vector
- [ ] Observe I-Cache hit/miss behavior
- [ ] Observe branch prediction and misprediction recovery

### 2.2 IDU (Instruction Decode Unit) - 10 files
```
gen_rtl/idu/rtl/
```
| Module | Focus |
|--------|-------|
| `aq_idu_top.v` | Top-level |
| `aq_idu_id_decd.v` | Main decoder (opcode -> control signals) |
| `aq_idu_id_gpr.v` | 32x64-bit General Purpose Register file |
| `aq_idu_id_wbt.v` | Write-Back scoreboard (hazard tracking) |
| `aq_idu_id_split.v` | Complex instruction splitting |
| `aq_idu_expand_32.v` | Compressed (16-bit) instruction expansion |

#### Simulation Exercises
- [ ] Trace an `ADD` instruction through decode
- [ ] Observe register read ports and operand forwarding
- [ ] Identify pipeline stalls caused by data hazards (WBT)

---

## Phase 3: CPU Pipeline Back-End (Week 4-5)

### 3.1 IU (Integer Execution Unit) - 9 files
```
gen_rtl/iu/rtl/
```
| Module | Focus |
|--------|-------|
| `aq_iu_alu.v` | ALU operations (add, sub, logic, shift) |
| `aq_iu_mul.v` | Multiplier (Booth encoding) |
| `aq_iu_div.v` | Divider (radix-2 shift) |
| `aq_iu_bju.v` | Branch/Jump resolution |
| `booth_code_33_bit.v` | Booth encoder for multiplication |
| `multiplier_33x33_partial.v` | Partial product array |

#### Simulation Exercises
```bash
make runcase CASE=ISA_INT SIM=iverilog DUMP=on
```
- [ ] Trace ADD/SUB/AND/OR through ALU datapath
- [ ] Observe MUL latency and Booth encoding
- [ ] Trace DIV operation cycle by cycle
- [ ] Observe branch resolution and pipeline flush on misprediction

### 3.2 RTU (Retire Unit) - 7 files
```
gen_rtl/rtu/rtl/
```
| Module | Focus |
|--------|-------|
| `aq_rtu_top.v` | Top-level |
| `aq_rtu_retire.v` | In-order retirement logic |
| `aq_rtu_wb.v` | Write-back to register file |
| `aq_rtu_int.v` | Interrupt handling at retire |
| `aq_rtu_rbus.v` | Result bus arbitration |

#### Simulation Exercises
- [ ] Observe `core0_pad_retire` signal (instruction retirement)
- [ ] Trace `retire_pc` to verify instruction flow
- [ ] Count IPC (Instructions Per Cycle) during test execution

---

## Phase 4: Memory Subsystem (Week 6-7)

### 4.1 LSU (Load Store Unit) - 34 files
```
gen_rtl/lsu/rtl/
```
| Module | Focus |
|--------|-------|
| `aq_lsu_top.v` | Top-level |
| `aq_lsu_ag.v` | Address generation |
| `aq_dcache_top.v` | D-Cache (tag/data/dirty arrays) |
| `aq_lsu_stb.v` | Store buffer |
| `aq_lsu_lfb.v` | Load fill buffer (cache miss handling) |
| `aq_lsu_pfb.v` | Hardware prefetch buffer |
| `aq_lsu_amo_alu.v` | Atomic memory operations (LR/SC, AMO) |
| `aq_lsu_vb.v` | Victim buffer (write-back cache eviction) |

#### Simulation Exercises
```bash
make runcase CASE=ISA_LS SIM=iverilog DUMP=on
make runcase CASE=cache SIM=iverilog DUMP=on
```
- [ ] Trace a LOAD instruction: address gen -> TLB -> cache lookup -> data return
- [ ] Observe cache miss -> fill buffer -> bus request -> data fill
- [ ] Trace a STORE: store buffer write -> cache update
- [ ] Observe atomic operation (AMO) execution

### 4.2 MMU (Memory Management Unit) - 16 files
```
gen_rtl/mmu/rtl/
```
| Module | Focus |
|--------|-------|
| `aq_mmu_top.v` | Top-level |
| `aq_mmu_utlb.v` | Micro-TLB (L1 TLB, fully associative) |
| `aq_mmu_jtlb.v` | Joint-TLB (L2 TLB, set associative) |
| `aq_mmu_ptw.v` | Page Table Walker (hardware) |
| `aq_mmu_plru.v` | Pseudo-LRU replacement policy |
| `aq_mmu_sysmap.v` | System address mapping |

#### Simulation Exercises
```bash
make runcase CASE=MMU SIM=iverilog DUMP=on
```
- [ ] Trace virtual-to-physical address translation
- [ ] Observe TLB miss -> PTW -> page table walk
- [ ] Understand Sv39 page table format in C906

### 4.3 BIU (Bus Interface Unit) - 6 files
```
gen_rtl/biu/rtl/
```
- [ ] Trace AXI read/write transactions
- [ ] Observe burst transfers for cache line fills
- [ ] Understand request arbitration between I-Cache and D-Cache

---

## Phase 5: Privileged Architecture & System (Week 8-9)

### 5.1 CP0 (System Control) - 15 files
```
gen_rtl/cp0/rtl/
```
| Module | Focus |
|--------|-------|
| `aq_cp0_regs.v` | CSR register file |
| `aq_cp0_trap_csr.v` | Trap-related CSRs (mtvec, mepc, mcause) |
| `aq_cp0_info_csr.v` | Machine info CSRs (misa, mvendorid) |
| `aq_cp0_cache_inst.v` | Cache maintenance instructions |
| `aq_cp0_fence_inst.v` | FENCE/FENCE.I handling |
| `aq_cp0_lpmd.v` | Low-power mode (WFI) |

#### Simulation Exercises
```bash
make runcase CASE=csr SIM=iverilog DUMP=on
make runcase CASE=exception SIM=iverilog DUMP=on
make runcase CASE=interrupt SIM=iverilog DUMP=on
```
- [ ] Trace CSR read/write operations (csrrw, csrrs, csrrc)
- [ ] Observe exception flow: trap entry -> mtvec -> handler -> mret
- [ ] Observe interrupt: PLIC -> pending -> taken -> handler

### 5.2 PMP (Physical Memory Protection) - 4 files
```
gen_rtl/pmp/rtl/
```
- [ ] Understand PMP address matching (TOR, NAPOT, NA4)
- [ ] Trace access violation detection

### 5.3 Interrupt System
| Module | Location |
|--------|----------|
| CLINT (timer) | `gen_rtl/clint/rtl/` - 2 files |
| PLIC (external) | `gen_rtl/plic/rtl/` - 11 files |

- [ ] Trace timer interrupt: mtime >= mtimecmp -> interrupt pending
- [ ] Trace external interrupt through PLIC priority arbitration

---

## Phase 6: Floating-Point & Vector Extensions (Week 10-11)

### 6.1 FPU Pipeline
| Unit | Files | Function |
|------|-------|----------|
| VFALU | 22 files | FP add/sub/compare/convert |
| VFMAU | 11 files | FP multiply-accumulate (FMA) |
| VFDSU | 12 files | FP divide/sqrt (SRT algorithm) |
| VIDU | 8 files | FP/Vector instruction decode |

#### Simulation Exercises
```bash
make runcase CASE=ISA_FP SIM=iverilog DUMP=on
```
- [ ] Trace FADD.D through the VFALU pipeline
- [ ] Observe FMA operation in VFMAU (fused multiply-add)
- [ ] Trace FDIV.D through SRT division algorithm
- [ ] Understand IEEE 754 rounding modes in hardware

### 6.2 Key FPU Modules to Study
| Module | Key Concept |
|--------|-------------|
| `aq_fadd_double_top.v` | Double-precision addition pipeline |
| `aq_fadd_double_round.v` | IEEE 754 rounding implementation |
| `aq_vfmau_frac_mult.v` | Fraction multiplication (mantissa) |
| `aq_vfmau_lza_double.v` | Leading Zero Anticipator (normalization) |
| `aq_fdsu_srt.v` | SRT division core algorithm |
| `booth_code_54_bit.v` | Booth encoding for FP multiplier |

---

## Phase 7: Debug & Performance (Week 12)

### 7.1 Debug Infrastructure
```
gen_rtl/dtu/rtl/  (12 files) - CPU debug unit
gen_rtl/tdt/rtl/  (18 files) - RISC-V Debug Spec (0.13)
```
```bash
make runcase CASE=debug SIM=iverilog DUMP=on
```
- [ ] Trace JTAG -> DTM -> DMI -> DM communication
- [ ] Observe hardware breakpoint trigger
- [ ] Understand halt/resume debug flow

### 7.2 Performance Monitoring (PMU) - 6 files
```
gen_rtl/pmu/rtl/
```
- [ ] Understand hardware performance counters (mcycle, minstret, mhpmcounter)
- [ ] Trace event counting (cache miss, branch misprediction, etc.)

---

## Phase 8: SoC Integration & Advanced Topics (Week 13+)

### 8.1 SoC Testbench Architecture
```
smart_run/logical/
├── common/soc.v              # SoC top (CPU + bus + peripherals)
├── common/cpu_sub_system_axi.v  # CPU AXI wrapper
├── axi/                     # AXI interconnect
├── ahb/                     # AHB bus bridge
├── apb/                     # APB peripheral bus
├── uart/                    # UART controller
├── gpio/                    # GPIO controller
├── mem/                     # Memory controller & SRAM models
└── tb/tb.v                  # Testbench
```
- [ ] Trace AXI -> AHB -> APB bus transaction
- [ ] Understand UART output mechanism (how printf works in simulation)
- [ ] Study memory controller and SRAM timing model

### 8.2 Advanced Exercises
- [ ] Write a custom assembly test case and run it
- [ ] Modify cache parameters and observe performance impact
- [ ] Run CoreMark benchmark and analyze IPC
  ```bash
  make runcase CASE=coremark SIM=iverilog
  ```
- [ ] Add a custom hardware performance counter event
- [ ] Try FPGA synthesis targeting your board (using `impl/` SDC files)

---

## Appendix: Module Map (253 Verilog files)

```
gen_rtl/
├── ifu/    (23) Instruction Fetch - ICache, BHT, BTB, RAS
├── idu/    (10) Instruction Decode - Decoder, GPR, Scoreboard
├── iu/      (9) Integer Execute - ALU, MUL, DIV, BJU
├── lsu/    (34) Load/Store - DCache, STB, LFB, PFB, VLSU
├── mmu/    (16) Memory Management - uTLB, jTLB, PTW
├── rtu/     (7) Retire - In-order commit, Write-back
├── cp0/    (15) System Control - CSRs, Trap, Cache ops
├── biu/     (6) Bus Interface - AXI master
├── pmp/     (4) Physical Memory Protection
├── pmu/     (6) Performance Monitoring
├── dtu/    (12) Debug Transfer Unit
├── tdt/    (18) RISC-V Debug (JTAG/DTM/DM)
├── clint/   (2) Core Local Interrupt Timer
├── plic/   (11) Platform Level Interrupt Controller
├── vidu/    (8) Vector/FP Decode
├── vfalu/  (22) FP Add/Sub/Compare/Convert
├── vfmau/  (11) FP Multiply-Accumulate
├── vfdsu/  (12) FP Divide/Square Root
├── vdsp/    (5) Vector Processing Unit
├── vdiv/    (1) Vector Divide helper
├── cpu/     (7) Top-level wrappers
├── clk/     (2) Clock generation & gating
├── rst/     (1) Reset
├── fpga/    (9) FPGA RAM implementations
└── common/  (2) CDC, buffers
```

---

## Recommended Reading Order

1. **Testbench** (`tb.v`, `soc.v`) - Understand simulation framework
2. **Top-down** (`openC906.v` -> `aq_top.v` -> `aq_core.v`) - Module hierarchy
3. **Pipeline front-end** (IFU -> IDU) - Instruction flow
4. **Pipeline back-end** (IU -> RTU) - Execution and retirement
5. **Memory** (LSU -> MMU -> BIU) - Data path
6. **System** (CP0 -> CLINT/PLIC -> PMP) - Privileged architecture
7. **FPU** (VFALU -> VFMAU -> VFDSU) - Floating-point
8. **Debug** (DTU -> TDT) - Debug infrastructure
