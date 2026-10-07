// ============================================================================
// study_tbdev.v  -  학습용 TB 장치 : SoC 외부 인터럽트 선 2 개를 구동한다
//
//  * 원본 tb.v / CPU RTL 은 수정하지 않는다. SoC 쪽은 tb/soc_overlay/cpu_sub_system_axi.v 가
//    외부 인터럽트 입력(study_ext_irq[1:0])을 하나 더 받도록 바뀌어 있고, 이 모듈이 그 reg 를
//    계층 참조로 쓴다. (Verilator 5.020 은 다른 모듈 신호에 대한 force 를 지원하지 않는다)
//      선 0 -> xx_intc_int[19] -> PLIC ID 35       선 1 -> xx_intc_int[20] -> PLIC ID 36   (level)
//  * 테스트 프로그램은 보통 장치처럼 store 로 제어한다 (common/study.h 의 TBDEV_*).
//      TBDEV_BASE + 0x00  IRQ0_SET = N : N 사이클 뒤에 선 0 을 1 로 (N = 0 이면 다음 사이클)
//      TBDEV_BASE + 0x08  IRQ0_CLR     : 선 0 을 바로 0 으로
//      TBDEV_BASE + 0x10 / 0x18        : 선 1 의 SET / CLR
//    TBDEV_BASE 는 일반 메모리(cacheable)라서 store 가 버스로 나가지 않는다. 그래서 LSU DC 단계에서
//    store buffer 로 들어가는 순간(dc_stb_req)을 감지한다. 메모리에도 그대로 써진다.
//  * 콘솔에 "[tbdev] ..." 로그를 남긴다.
// ============================================================================
`timescale 1ns/100ps

`define TD_CPU_TOP tb.x_soc.x_cpu_sub_system_axi.x_c906_wrapper.x_cpu_top
`define TD_DC      `TD_CPU_TOP.x_aq_top_0.x_aq_core.x_aq_lsu_top.x_aq_lsu_dc
`define TD_IRQ     tb.x_soc.x_cpu_sub_system_axi.study_ext_irq

module study_tbdev;
  localparam [39:0] BASE = 40'h1FFC0;      // common/study.h 의 TBDEV_BASE 와 같아야 한다

  wire        clk   = `TD_CPU_TOP.pll_core_cpuclk;
  wire        rst_b = `TD_CPU_TOP.pad_cpu_rst_b;
  reg  [31:0] cycle;                       // study_probe.cycle 과 같은 값
  always @(posedge clk or negedge rst_b)
    if (!rst_b) cycle <= 32'd0;
    else        cycle <= cycle + 32'd1;

  // ---------------------------------------------------------------- store 감지
  wire        st_req  = `TD_DC.dc_stb_req;          // store 가 DC 단계를 통과해 store buffer 로
  wire [39:0] st_pa   = `TD_DC.dc_stb_pa;
  wire [63:0] st_data = `TD_DC.dc_stb_data;         // 8 바이트 정렬 주소면 회전 없이 rs2 값 그대로
  wire        st_depd = `TD_DC.dc_stb_src2_depd;    // 데이터가 아직 준비 안 됨 (앞 명령 결과 대기)
  wire        st_hit  = st_req && st_pa[39:5] == BASE[39:5];
  wire        st_line = st_pa[4];                   // 0x00/0x08 -> 선 0, 0x10/0x18 -> 선 1
  wire        st_clr  = st_pa[3];

  // ---------------------------------------------------------------- 선 2 개
  reg  [31:0] cnt  [0:1];                  // 0 이 아니면 남은 사이클
  reg  [31:0] t_up [0:1];
  integer i;
  initial for (i = 0; i < 2; i = i + 1) begin cnt[i] = 0; t_up[i] = 0; end

  always @(posedge clk) begin
    for (i = 0; i < 2; i = i + 1) begin
      if (cnt[i] == 32'd1) begin
        `TD_IRQ[i] <= 1'b1;
        t_up[i]    <= cycle;
        $display("[tbdev] cycle %0d: irq%0d = 1  (PLIC ID %0d)", cycle, i, 35 + i);
      end
      if (cnt[i] != 0) cnt[i] <= cnt[i] - 32'd1;
    end
    if (st_hit) begin
      if (st_clr) begin
        cnt[st_line] <= 0;
        `TD_IRQ[st_line] <= 1'b0;
        $display("[tbdev] cycle %0d: irq%0d = 0  (CLR, %0d cycles high)",
                 cycle, st_line, `TD_IRQ[st_line] ? cycle - t_up[st_line] : 0);
      end else begin
        if (st_depd)
          $display("[tbdev] cycle %0d: WARNING IRQ%0d_SET data not ready at DC (use a register set earlier)",
                   cycle, st_line);
        cnt[st_line] <= st_data[31:0] + 32'd1;
        $display("[tbdev] cycle %0d: IRQ%0d_SET %0d", cycle, st_line, st_data[31:0]);
      end
    end
  end

endmodule
