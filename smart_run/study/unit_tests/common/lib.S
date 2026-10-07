/* ==========================================================================
 * lib.S - 콘솔 출력
 *   "csrw mscratch, ch" 한 번이 문자 하나. study_probe 가 mscratch 쓰기를 감지해
 *   시뮬레이터 콘솔에 찍는다. (UART 0x10015000 은 이 SoC 의 sysmap 에서
 *   cacheable 영역이라 sw 가 D-Cache 에만 머물러 버스로 나가지 않는다)
 *   테스트 코드는 mscratch 를 다른 용도로 쓰지 말 것.
 *   clobber: a0-a3, t0-t2, ra
 * ========================================================================== */
#include "study.h"

  .text
/* putc(a0 = char) */
  .globl putc
putc:
  csrw mscratch, a0
  ret

/* puts(a0 = NUL 종료 문자열) */
  .globl puts
puts:
  mv   t1, a0
1:
  lbu  t2, 0(t1)
  beqz t2, 2f
  csrw mscratch, t2
  addi t1, t1, 1
  j    1b
2:
  ret

/* putdec(a0 = unsigned 64-bit) */
  .globl putdec
putdec:
  addi sp, sp, -32
  mv   t1, sp                    /* 버퍼 끝에서부터 채움 */
  addi t1, t1, 31
  sb   zero, 0(t1)
  li   t2, 10
1:
  remu a1, a0, t2
  divu a0, a0, t2
  addi a1, a1, '0'
  addi t1, t1, -1
  sb   a1, 0(t1)
  bnez a0, 1b
2:
  lbu  a1, 0(t1)
  beqz a1, 3f
  csrw mscratch, a1
  addi t1, t1, 1
  j    2b
3:
  addi sp, sp, 32
  ret

/* puthex(a0) : 0x 접두어 + 16 자리 */
  .globl puthex
puthex:
  li   a1, '0'
  csrw mscratch, a1
  li   a1, 'x'
  csrw mscratch, a1
  li   t1, 60
1:
  srl  a1, a0, t1
  andi a1, a1, 0xf
  li   t2, 10
  blt  a1, t2, 2f
  addi a1, a1, 'a' - 10
  j    3f
2:
  addi a1, a1, '0'
3:
  csrw mscratch, a1
  addi t1, t1, -4
  bgez t1, 1b
  ret

/* report(a0 = name, a1 = value) : "@@ name = value\n" */
  .globl report
report:
  addi sp, sp, -16
  sd   ra, 0(sp)
  sd   a1, 8(sp)
  mv   a3, a0
  li   a0, '@'
  csrw mscratch, a0
  csrw mscratch, a0
  li   a0, ' '
  csrw mscratch, a0
  mv   a0, a3
  call puts
  li   a0, ' '
  csrw mscratch, a0
  li   a0, '='
  csrw mscratch, a0
  li   a0, ' '
  csrw mscratch, a0
  ld   a0, 8(sp)
  call putdec
  li   a0, '\n'
  csrw mscratch, a0
  ld   ra, 0(sp)
  addi sp, sp, 16
  ret
