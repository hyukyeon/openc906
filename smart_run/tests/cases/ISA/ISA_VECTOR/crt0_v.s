/* Modified crt0 for RVV tests — GCC 13 / rv64imafdcv compatible
 * Changes from original crt0.s:
 *   - Replace 'csrs mxstatus' with numeric CSR 0x7c0 (T-Head extension)
 *   - Remove .ifdef C906FDV block (used vsetvli e128 not valid in RVV 1.0)
 *   - Add mstatus.VS enable so vector instructions work in M-mode
 */

	.text

	.global	__start
__start:

# enable T-Head extension CSR (mxstatus = 0x7c0)
  li   x3, 0x400000
  csrs 0x7c0, x3

# enable FPU (mstatus.FS = 0b11)
  li   x3, 0x802000
  csrs mstatus, x3

# enable Vector unit (mstatus.VS[10:9] = 0b01 → initial)
  li   x3, 0x200
  csrs mstatus, x3

# PART 1: initialize integer registers
  li  x1, 0
  li  x2, 0
  li  x3, 0
  li  x4, 0
  li  x5, 0
  li  x6, 0
  li  x7, 0
  li  x8, 0
  li  x9, 0
  li  x10,0
  li  x11,0
  li  x12,0
  li  x13,0
  li  x14,0
  li  x15,0
  li  x16,0
  li  x17,0
  li  x18,0
  li  x19,0
  li  x20,0
  li  x21,0
  li  x22,0
  li  x23,0
  li  x24,0
  li  x25,0
  li  x26,0
  li  x27,0
  li  x28,0
  li  x29,0
  li  x30,0
  li  x31,0

  .global cpu_0_sp
cpu_0_sp:
  la x2, __kernel_stack

# PART 3: initialize mtvec
  la    x3, __trap_handler
  csrw  mtvec, x3

  # enable MIE (machine interrupt enable)
  li   x3, 0x8
  csrs mstatus, x3

  # invalidate BTB/BHT/D$/I$ (mcor = 0x7c2)
  li x3, 0x30013
  csrs 0x7c2, x3

  # enable I$/D$/BHT/BTB/RAS/WA (mhcr = 0x7c1)
  li x3, 0x7f
  csrs 0x7c1, x3

  # enable data prefetch / AMR (mhint = 0x7c5)
  li x3, 0x610c
  csrs 0x7c5, x3

  jal main


  .global __exit
__exit:
  addi x10, x0, 0x0
  addi x1,  x0, 0x5a
  addi x2,  x0, 0x6b
  addi x3,  x0, 0x7c
  li   x3, 0x444333222      # testbench PASS magic
  add  x4, x0, x3
#
  .global __fail
__fail:
  addi x10, x0, 0x0
  addi x1,  x0, 0x2c
  addi x2,  x0, 0x3b
  li   x3, 0x2382348720     # testbench FAIL magic

.section .text
__trap_handler:
  j __synchronous_exception
  .align 2
  j __asychronous_int
  .align 2
  nop
  .align 2
  j __asychronous_int
  .align 2
  j __asychronous_int
  .align 2
  j __asychronous_int
  .align 2
  nop
  .align 2
  j __asychronous_int
  .align 2
  j __asychronous_int
  .align 2
  j __asychronous_int
  .align 2
  nop
  .align 2
  j __asychronous_int
  j __fail

__synchronous_exception:
  sd   x14, -16(sp)
  sd   x15, -24(sp)
  csrr x14, mcause
  andi x15, x14, 0x1f
  srli x14, x14, 0x3b
  andi x14, x14, 0x10
  add  x14, x14, x15
  slli x14, x14, 0x3
  la   x15, vector_table
  add  x15, x14, x15
  ld   x14, 0(x15)
  ld   x15, -24(sp)
  addi x14, x14, -4
  jr   x14

__asychronous_int:
  sw   x13, -4(sp)
  sw   x14, -8(sp)
  sw   x15, -12(sp)
  csrr x14, mcause
  andi x15, x14, 0x1f
  srli x14, x14, 0x3b
  andi x14, x14, 0x10
  add  x14, x14, x15
  slli x14, x14, 0x3
  la   x15, vector_table
  add  x15, x14, x15
  lw   x14, 0(x15)
  lw   x13, -4(sp)
  lw   x15, -12(sp)
  addi x14, x14, -4
  jr   x14

.global vector_table
  .align 10
  vector_table:
  .rept 128
  .dword __fail    /* 8-byte entries — matches 'ld' in __synchronous_exception */
  .endr

  .global __dummy
__dummy:

  .data
  nop
  nop
  nop
