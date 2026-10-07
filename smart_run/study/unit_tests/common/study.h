/* ==========================================================================
 * study.h - 학습용 어셈블리 테스트 공통 매크로
 *
 *  레지스터 규약
 *    x31(t6) : MARK 전용. "li x31, n" 이 실행되면 study_probe 의 mark 신호가 n 이 되어
 *              VCD/trace 에서 구간을 찾기 쉽다. 테스트 코드에서 다른 용도로 쓰지 말 것.
 *    lib.S 함수(putc/puts/putdec/puthex/report)는 a0-a3, t0-t2, ra 를 덮어쓴다.
 * ========================================================================== */
#ifndef STUDY_H
#define STUDY_H

#define UART_TX        0x10015000      /* tb.v 가 이 주소로의 AXI write 를 콘솔로 출력 */
/* CLINT: 상위 13bit 는 SoC 가 지정(pad_cpu_apb_base = 0x40_0000_0000), 하위 27bit 는 UM 표 9.1
 *        mtime 은 MMIO 가 아니라 time CSR(rdtime) 로 읽는다. 모든 레지스터는 word(sw/lw) 접근만 */
#define CLINT_BASE      0x4004000000
#define CLINT_MSIP0     (CLINT_BASE + 0x0000)
#define CLINT_MTIMECMPL (CLINT_BASE + 0x4000)
#define CLINT_MTIMECMPH (CLINT_BASE + 0x4004)
#define CLINT_SSIP0     (CLINT_BASE + 0xC000)   /* S 모드 소프트웨어 인터럽트 (C906 확장, MXSTATUS.CLINTEE) */

/* PLIC (UM 9장, plic_top.v): base = pad_cpu_apb_base. hart 0 의 M 컨텍스트 / S 컨텍스트
 *   소스 ID 0 = 없음, 1 = L2 ECC, 2~15 = 예약, 16 부터 = SoC 의 pad_plic_int_vld[0..] */
#define PLIC_BASE       0x4000000000
#define PLIC_PRIO(id)   (PLIC_BASE + 4 * (id))          /* 우선순위 0(끔)~31             */
#define PLIC_IP0        (PLIC_BASE + 0x1000)            /* pending 비트맵 (ID 0~31)       */
#define PLIC_IP1        (PLIC_BASE + 0x1004)            /* pending 비트맵 (ID 32~63)      */
#define PLIC_H0_MIE1    (PLIC_BASE + 0x2004)            /* M 컨텍스트 enable (ID 32~63)   */
#define PLIC_H0_SIE1    (PLIC_BASE + 0x2084)            /* S 컨텍스트 enable (ID 32~63)   */
#define PLIC_H0_MTH     (PLIC_BASE + 0x200000)          /* M 컨텍스트 threshold           */
#define PLIC_H0_MCLAIM  (PLIC_BASE + 0x200004)          /* M 컨텍스트 claim / complete    */
#define PLIC_H0_STH     (PLIC_BASE + 0x201000)          /* S 컨텍스트 threshold           */
#define PLIC_H0_SCLAIM  (PLIC_BASE + 0x201004)          /* S 컨텍스트 claim / complete    */

/* TB 장치 (tb/study_tbdev.v) : 이 주소로의 store 를 테스트벤치가 감지한다 (메모리에도 그대로 써진다).
 *   외부 인터럽트 선 0 -> SoC xx_intc_int[19] -> PLIC ID 35,  선 1 -> [20] -> ID 36   (level)
 *   IRQn_SET 에 N 을 쓰면 N 사이클 뒤에 선 n 을 1 로, IRQn_CLR 에 쓰면 바로 0 으로 내린다.
 *   SET 에 쓰는 값은 store 직전에 준비된 레지스터여야 한다 (DC 단계에서 데이터를 읽는다). */
#define TBDEV_BASE      0x1FFC0
#define TBDEV_IRQ0_SET  0x00
#define TBDEV_IRQ0_CLR  0x08
#define TBDEV_IRQ1_SET  0x10
#define TBDEV_IRQ1_CLR  0x18
#define TB_IRQ0_ID      35
#define TB_IRQ1_ID      36

/* 인터럽트 플래그 (p5_sys06) : 고정 주소의 일반 메모리 word. study_probe 가 이 주소로의 store 를 감지해
 *   파형에 int_flag 로 보여 준다 (TBDEV 범위 0x1FFC0~0x1FFDF 바로 다음). C 로 쓰면
 *   #define int_flag (*(volatile uint32_t *)INT_FLAG_ADDR)                                        */
#define INT_FLAG_ADDR   0x1FFE0

/* C906 확장 CSR (T-Head) */
#define CSR_MXSTATUS   0x7c0
#define CSR_MHCR       0x7c1
#define CSR_MCOR       0x7c2
#define CSR_MHINT      0x7c5

/* MHCR bits : aq_cp0_ext_csr.v  mhcr_value = {..., ibpe, btbe, bpe, rse, wb, wa, de, ie} */
#define MHCR_IE   (1 << 0)   /* I-Cache enable              */
#define MHCR_DE   (1 << 1)   /* D-Cache enable              */
#define MHCR_WA   (1 << 2)   /* write-allocate              */
#define MHCR_WB   (1 << 3)   /* write-back (C906 는 항상 1)  */
#define MHCR_RS   (1 << 4)   /* RAS enable                  */
#define MHCR_BPE  (1 << 5)   /* BHT(방향 예측) enable        */
#define MHCR_BTB  (1 << 6)   /* BTB enable                  */
#define MHCR_DEFAULT (MHCR_IE | MHCR_DE | MHCR_WA | MHCR_WB | MHCR_RS | MHCR_BPE | MHCR_BTB)

/* MHINT bits : mhint_value = {..., dcache_pref_dist[14:13], 0, sre, iwpe, lpe, icache_pref_en(8), 00, amr2, amr[4:3], dcache_pref_en(2), 00} */
#define MHINT_DPLD  (1 << 2)  /* D-Cache prefetch */
#define MHINT_IPLD  (1 << 8)  /* I-Cache prefetch */

/* HPM 이벤트 번호 (C906 UM 표 12.9) - crt0 가 아래처럼 counter 3~9 에 연결해 둔다 */
#define HPM_BR_MISPRED   0x06   /* mhpmcounter3 : 조건 분기 예측 실패        */
#define HPM_BR_COND      0x07   /* mhpmcounter4 : 조건 분기 명령 수          */
#define HPM_IC_MISS      0x02   /* mhpmcounter5 : I-Cache miss              */
#define HPM_DC_RD_ACC    0x0C   /* mhpmcounter6 : D-Cache read access        */
#define HPM_DC_RD_MISS   0x0D   /* mhpmcounter7 : D-Cache read miss          */
#define HPM_FE_STALL     0x27   /* mhpmcounter8 : front-end stall cycles     */
#define HPM_BE_STALL     0x28   /* mhpmcounter9 : back-end  stall cycles     */

#ifdef __ASSEMBLER__

#define MARK(n)   li x31, n

/* 측정: TIC 로 시작 사이클을 r 에 저장, TOC 로 r = 경과 사이클 */
#define TIC(r)    csrr r, mcycle
#define TOC(r)    csrr t0, mcycle; sub r, t0, r

/* MHCR 을 v 로 설정 (식에 공백이 있어도 되도록 cpp 매크로로 정의) */
#define SET_MHCR(v)  li t0, (v); csrw CSR_MHCR, t0

/* "@@ name = value" 형식으로 출력 (collect_results.py 가 수집) */
.macro REPORT name:req, reg:req
  .pushsection .rodata.str, "a"
.Lrep_\@: .asciz "\name"
  .popsection
  mv   a1, \reg
  la   a0, .Lrep_\@
  call report
.endm

.macro PRINT str:req
  .pushsection .rodata.str, "a"
.Lstr_\@: .asciz "\str"
  .popsection
  la   a0, .Lstr_\@
  call puts
.endm

/* BHT/BTB 내용 무효화 (MCOR.bht_inv/btb_inv, 완료되면 HW 가 비트를 0 으로) */
.macro INV_BP
  li   t0, (1 << 17) | (1 << 16)
  csrs CSR_MCOR, t0
.Linv_\@:
  csrr t1, CSR_MCOR
  and  t1, t1, t0
  bnez t1, .Linv_\@
.endm


/* 값이 다르면 FAIL */
.macro EXPECT reg:req, val:req
  li   t0, \val
  beq  \reg, t0, .Lok_\@
  j    fail
.Lok_\@:
.endm

/* n 번 반복되는 코드 블록 */
.macro REPEAT n:req, insn:vararg
  .rept \n
  \insn
  .endr
.endm

#endif /* __ASSEMBLER__ */
#endif /* STUDY_H */
