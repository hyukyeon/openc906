/* tb.v 는 inst.pat 을 0x0 부터, data.pat 을 0x40000 부터 메모리에 적재한다 */
OUTPUT_ARCH(riscv)
ENTRY(_start)

MEMORY
{
  TEXT (rx) : ORIGIN = 0x00000000, LENGTH = 0x8000    /* asm_rom 이 커버하는 32KB */
  DATA (rw) : ORIGIN = 0x00040000, LENGTH = 0x40000
}

SECTIONS
{
  .text   : { *(.text.init) *(.text .text.*) } > TEXT
  .rodata : { *(.rodata .rodata.* .srodata .srodata.*) } > TEXT
  .data   : { *(.data .data.* .sdata .sdata.*) } > DATA
  .bss    : { *(.bss .bss.* .sbss .sbss.* COMMON) } > DATA
  __stack_top = ORIGIN(DATA) + LENGTH(DATA) - 16;
}
