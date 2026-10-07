// ============================================================================
// study_probe.v  -  OpenC906 학습용 관찰 모듈 (tb.v 는 수정하지 않음)
//
//  * tb 와 함께 컴파일되는 "두 번째 top 모듈"이다. tb 계층을 hierarchical
//    reference 로 들여다보기만 하고, 설계에는 아무 영향도 주지 않는다.
//  * 파이프라인 단계별 핵심 신호를 읽기 쉬운 이름으로 다시 묶어서
//    (fe_*, id_*, ex_*, lsu_*, rt_*, cp0_*, bus_*) VCD 로 덤프한다.
//  * PC 에 해당하는 디스어셈블리 문자열(asm_rom)을 ASCII 신호로 함께 덤프하므로
//    GTKWave 에서 "지금 EX1 에 어떤 명령어가 있는지" 를 바로 읽을 수 있다.
//  * 매 사이클 파이프라인 상태를 trace 로그(텍스트)로도 남긴다.
//
// plusargs
//   +vcd=<file>            : 관찰 신호(study_probe 스코프)를 VCD 로 덤프
//   +vcd_full              : aq_core 전체도 함께 덤프 (파일이 커짐)
//   +vcd_from_mark=<n>     : x31(mark) 이 n 이 되는 순간부터 덤프 시작
//   +vcd_to_mark=<n>       : x31(mark) 이 n 이 되는 순간 덤프 중지
//   +asm=<file>            : PC -> 디스어셈블리 ASCII ROM (tools/mk_asm_rom.py 생성)
//   +trace=<file>          : 사이클 trace 로그
//   +trace_all             : mark==0 (crt0 구간) 도 trace 에 기록
// ============================================================================
`timescale 1ns/100ps

`define SP_CPU_TOP tb.x_soc.x_cpu_sub_system_axi.x_c906_wrapper.x_cpu_top
`define SP_CORE    `SP_CPU_TOP.x_aq_top_0.x_aq_core
`define SP_IFU     `SP_CORE.x_aq_ifu_top
`define SP_IDU     `SP_CORE.x_aq_idu_top
`define SP_IU      `SP_CORE.x_aq_iu_top
`define SP_LSU     `SP_CORE.x_aq_lsu_top
`define SP_RTU     `SP_CORE.x_aq_rtu_top
`define SP_CP0     `SP_CORE.x_aq_cp0_top
`define SP_TRAP    `SP_CP0.x_aq_cp0_regs.x_aq_cp0_trap_csr
`define SP_PLIC    `SP_CPU_TOP.x_aq_plic_top
`define SP_CLINT   `SP_CPU_TOP.x_clint_top.x_clint_func

module study_probe;

  // --------------------------------------------------------------------------
  // 0. clock / cycle / mark
  // --------------------------------------------------------------------------
  wire        clk   = `SP_CPU_TOP.pll_core_cpuclk;
  wire        rst_b = `SP_CPU_TOP.pad_cpu_rst_b;
  reg  [31:0] cycle;                       // reset 해제 후 CPU 클럭 수
  always @(posedge clk or negedge rst_b)
    if (!rst_b) cycle <= 32'd0;
    else        cycle <= cycle + 32'd1;

  // 테스트 코드가 "li x31, n" 으로 구간 번호를 표시한다 (MARK 매크로)
  wire [63:0] mark  = `SP_IDU.x_aq_idu_id_gpr.x_aq_idu_id_gpr_gated_reg_31.reg_dout;

  // --------------------------------------------------------------------------
  // 1. Front-End : IF (pcgen/icache/BTB) -> IP (pred: pre-decode/BHT/RAS) -> IBUF
  // --------------------------------------------------------------------------
  wire [39:0] fe_if_pc        = `SP_IFU.x_aq_ifu_pcgen.pcgen_fetch_pc[39:0]; // 이번 사이클 I$ 접근 주소
  wire        fe_if_grant     = `SP_IFU.x_aq_ifu_pcgen.icache_pcgen_grant;    // I$ 가 요청을 받아들임
  wire        fe_btb_hit      = `SP_IFU.x_aq_ifu_btb.btb_rd_hit_vld;          // IF PC 로 BTB 조회 hit
  wire        fe_btb_redirect = `SP_IFU.x_aq_ifu_btb.btb_pred_flop;           // BTB 가 다음 fetch 를 돌림 (0-bubble)
  wire        fe_ip_vld0      = `SP_IFU.x_aq_ifu_pred.ipack_pred_inst0_vld;   // IP 단계 명령 0 유효
  wire        fe_ip_vld1      = `SP_IFU.x_aq_ifu_pred.ipack_pred_inst1_vld;   // IP 단계 명령 1 유효(16bit 2개)
  wire [39:0] fe_ip_pc        = `SP_IFU.x_aq_ifu_pred.pred_idpc[39:0];        // IP 단계 PC
  wire        fe_ip_br_taken  = `SP_IFU.x_aq_ifu_pred.pred_br_taken;          // pre-decode+BHT: taken 예측
  wire        fe_ip_redirect  = `SP_IFU.x_aq_ifu_pred.pred_chgflw_fin;        // IP 단계 redirect (1-bubble)
  wire [39:0] fe_ip_redir_pc  = `SP_IFU.x_aq_ifu_pred.pred_chgflw_fin_tar[39:0];
  wire        fe_ip_curflw    = `SP_IFU.x_aq_ifu_pred.pred_curflw;            // RAS ret / delay 분기 redirect
  wire        fe_btb_upd      = `SP_IFU.x_aq_ifu_pred.pred_btb_upd_vld;       // BTB 갱신
  wire        fe_btb_mispred  = `SP_IFU.x_aq_ifu_pred.btb_mis_pred;           // BTB 예측이 IP 결과와 다름
  wire [1:0]  fe_bht_pred     = `SP_IFU.x_aq_ifu_pred.x_aq_ifu_bht.bht_pred_rslt[1:0]; // 2-bit 카운터 값
  wire [13:0] fe_bht_ghr      = `SP_IFU.x_aq_ifu_pred.x_aq_ifu_bht.bht_ghr[13:0];      // 확정 전역 히스토리
  wire [13:0] fe_bht_vghr     = `SP_IFU.x_aq_ifu_pred.x_aq_ifu_bht.bht_vghr[13:0];     // 투기적 전역 히스토리
  wire        fe_ras_push     = `SP_IFU.x_aq_ifu_pred.pred_ras_link_vld;
  wire        fe_ras_pop      = `SP_IFU.x_aq_ifu_pred.pred_ras_ret_vld;
  wire [3:0]  fe_ras_ptr      = `SP_IFU.x_aq_ifu_pred.x_aq_ifu_ras.ras_pop[3:0];     // 투기적 top (one-hot)
  wire [3:0]  fe_ras_ptr_bju  = `SP_IFU.x_aq_ifu_pred.x_aq_ifu_ras.ras_bju[3:0];     // 확정 top (one-hot)
  wire        fe_ras_stall    = `SP_IFU.x_aq_ifu_pred.pred_ret_stall;         // ret 1개 미확정 상태에서 다음 ret
  wire [2:0]  fe_ibuf_num     = `SP_IFU.x_aq_ifu_ibuf.ibuf_vld_num[2:0];      // IBUF 유효 엔트리 수
  wire        fe_ic_access    = `SP_CORE.ifu_hpcp_icache_access;              // I-Cache 접근 (HPM 이벤트 소스)
  wire        fe_ic_miss      = `SP_CORE.ifu_hpcp_icache_miss;                // I-Cache miss

  // --------------------------------------------------------------------------
  // 2. Decode / Dispatch (ID) -> EX1 latch (IDU 안에 있음)
  // --------------------------------------------------------------------------
  wire        id_vld          = `SP_CORE.ifu_idu_id_inst_vld;
  wire [31:0] id_inst         = `SP_CORE.ifu_idu_id_inst[31:0];
  wire        id_dis_vld      = `SP_IDU.x_aq_idu_id_ctrl.ctrl_dis_inst_vld;
  wire        id_pipedown     = `SP_IDU.x_aq_idu_id_ctrl.ctrl_pipedown_inst_vld; // ID -> EX1 이동
  wire        id_stall        = `SP_IDU.x_aq_idu_id_ctrl.ctrl_dis_stall;
  wire        id_stall_raw    = `SP_IDU.x_aq_idu_id_ctrl.ctrl_dis_raw && id_dis_vld;  // RAW 로 stall
  wire        id_stall_waw    = `SP_IDU.x_aq_idu_id_ctrl.ctrl_dis_waw && id_dis_vld;  // WAW 로 stall
  wire        id_stall_ex1    = `SP_IDU.x_aq_idu_id_ctrl.ctrl_ex1_stall;     // EX1 이 못 빠짐(유닛 full 등)
  wire        id_stall_cp0    = `SP_IDU.x_aq_idu_id_ctrl.ctrl_dis_cp0_stall; // fence/csr 직렬화
  wire        id_stall_split  = `SP_IDU.x_aq_idu_id_ctrl.ctrl_split_stall;   // split(micro-op) 진행 중
  wire        id_stall_flush  = `SP_RTU.rtu_idu_flush_stall;

  // --------------------------------------------------------------------------
  // 3. Execute (EX1 / EX2 / EX3 ...)
  // --------------------------------------------------------------------------
  wire        ex1_vld         = `SP_IDU.x_aq_idu_id_ctrl.ex1_inst_vld;
  wire [9:0]  ex1_eu          = `SP_IDU.x_aq_idu_id_ctrl.ex1_eu_sel[9:0];   // one-hot: ALU,BJU,MUL,DIV,CP0,LSU,..,FP,VEC
  wire [39:0] ex1_pc          = `SP_CORE.iu_rtu_ex1_cur_pc[39:0];           // IU 가 자체 계산하는 EX1 PC
  wire        ex1_alu         = `SP_CORE.idu_iu_ex1_alu_sel;
  wire        ex1_bju         = `SP_CORE.idu_iu_ex1_bju_sel;
  wire        ex1_mul         = `SP_CORE.idu_iu_ex1_mult_sel;
  wire        ex1_div         = `SP_CORE.idu_iu_ex1_div_sel;
  wire        ex1_lsu         = `SP_CORE.idu_lsu_ex1_sel;
  wire        ex1_cp0         = `SP_CORE.idu_cp0_ex1_sel;
  // BJU (분기 판정)
  wire        bju_br_vld      = `SP_CORE.iu_ifu_br_vld;          // 조건 분기 판정 완료
  wire        bju_br_taken    = `SP_CORE.iu_ifu_bht_taken;       // 실제 taken 여부 (GHR 에 shift-in)
  wire        bju_bht_mispred = `SP_CORE.iu_ifu_bht_mispred;     // 방향 예측 실패
  wire        bju_jalr_mispred= `SP_CORE.iu_ifu_pc_mispred;      // rs1!=ra 인 JALR (항상 redirect)
  wire        bju_ras_mispred = `SP_CORE.iu_rtu_ex2_bju_ras_mispred; // RAS 예측 주소 틀림
  wire        iu_redirect     = `SP_CORE.iu_ifu_tar_pc_vld;      // IU -> IFU redirect (flush front-end)
  wire [39:0] iu_redirect_pc  = `SP_CORE.iu_ifu_tar_pc[39:0];
  // MUL / DIV
  wire        mul_wb          = `SP_CORE.iu_rtu_ex3_mul_wb_vld;  // EX3 에서 곱셈 결과 write-back
  wire        mul_full        = `SP_CORE.iu_idu_mult_full;
  wire        div_busy        = `SP_CORE.iu_idu_div_full;        // 나눗셈기 사용 중
  wire        div_wb          = `SP_CORE.iu_rtu_div_wb_vld;

  // --------------------------------------------------------------------------
  // 4. LSU : AG(=EX1) -> DC(=EX2) -> (miss 시 LFB/BIU)
  // --------------------------------------------------------------------------
  wire        lsu_ag_vld      = `SP_LSU.x_aq_lsu_ag.ag_inst_vld;
  wire [39:0] lsu_ag_va       = `SP_LSU.x_aq_lsu_ag.ag_addr[39:0];
  wire        lsu_dc_vld      = `SP_LSU.x_aq_lsu_dc.dc_inst_vld;
  wire [39:0] lsu_dc_pa       = `SP_LSU.x_aq_lsu_dc.dc_pa[39:0];
  wire        lsu_dc_ld       = `SP_LSU.x_aq_lsu_dc.dc_ld_inst;
  wire        lsu_dc_st       = `SP_LSU.x_aq_lsu_dc.dc_st_inst;
  wire        lsu_dc_hit      = `SP_LSU.x_aq_lsu_dc.dc_cache_hit;
  wire        lsu_dc_miss     = `SP_LSU.x_aq_lsu_dc.dc_cache_miss;
  wire        lsu_stb_fwd     = `SP_LSU.x_aq_lsu_dc.dc_ld_fwd_sel && `SP_LSU.x_aq_lsu_dc.dc_ld_inst; // STB -> load forwarding
  wire        lsu_stb_part    = `SP_LSU.x_aq_lsu_dc.stb_dc_multi_or_part_hit && lsu_dc_vld && `SP_LSU.x_aq_lsu_dc.dc_ld_inst; // STB 부분 겹침(forward 불가)
  wire        lsu_ld_data_vld = `SP_CORE.lsu_rtu_ex2_data_vld;     // load 데이터 반환(EX2)
  wire        lsu_full        = `SP_CORE.lsu_idu_full;
  wire        lsu_dc_rd_acc   = `SP_CORE.lsu_hpcp_cache_read_access;
  wire        lsu_dc_rd_miss  = `SP_CORE.lsu_hpcp_cache_read_miss;

  // --------------------------------------------------------------------------
  // 5. Retire / Write-back / Forwarding / Flush
  // --------------------------------------------------------------------------
  wire        rt_vld          = `SP_CORE.rtu_pad_retire;
  wire [39:0] rt_pc           = `SP_CORE.rtu_pad_retire_pc[39:0];
  wire        rt_flush        = `SP_CORE.rtu_yy_xx_flush;
  wire        rt_redirect     = `SP_CORE.rtu_ifu_chgflw_vld;     // RTU -> IFU redirect (trap/mret/fence.i..)
  wire [39:0] rt_redirect_pc  = `SP_CORE.rtu_ifu_chgflw_pc[39:0];
  wire        rt_expt         = `SP_CORE.rtu_yy_xx_expt_vld;     // 예외/인터럽트 진입
  wire        wb0_vld         = `SP_CORE.rtu_idu_wb0_vld;
  wire [5:0]  wb0_reg         = `SP_CORE.rtu_idu_wb0_reg;
  wire [63:0] wb0_data        = `SP_CORE.rtu_idu_wb0_data;
  wire        wb1_vld         = `SP_CORE.rtu_idu_wb1_vld;
  wire [5:0]  wb1_reg         = `SP_CORE.rtu_idu_wb1_reg;
  wire [63:0] wb1_data        = `SP_CORE.rtu_idu_wb1_data;
  wire        fwd0_vld        = `SP_CORE.rtu_idu_fwd0_vld;
  wire [5:0]  fwd0_reg        = `SP_CORE.rtu_idu_fwd0_reg;
  wire        fwd1_vld        = `SP_CORE.rtu_idu_fwd1_vld;
  wire [5:0]  fwd1_reg        = `SP_CORE.rtu_idu_fwd1_reg;
  wire        fwd2_vld        = `SP_CORE.rtu_idu_fwd2_vld;
  wire [5:0]  fwd2_reg        = `SP_CORE.rtu_idu_fwd2_reg;

  // --------------------------------------------------------------------------
  // 6. CP0 (trap CSR) / 특권 모드
  // --------------------------------------------------------------------------
  wire [1:0]  cp0_priv        = `SP_CP0.x_aq_cp0_regs.regs_pm[1:0];   // 11=M 01=S 00=U
  wire        cp0_mstatus_mie = `SP_TRAP.mie_bit;
  wire        cp0_mstatus_mpie= `SP_TRAP.mpie;
  wire [1:0]  cp0_mstatus_mpp = `SP_TRAP.mpp[1:0];
  wire        cp0_mcause_int  = `SP_TRAP.m_intr;
  wire [4:0]  cp0_mcause_code = `SP_TRAP.m_vector[4:0];
  wire [63:0] cp0_mepc        = {`SP_TRAP.mepc_reg[62:0], 1'b0};
  wire [63:0] cp0_mtval       = `SP_TRAP.mtval_data[63:0];
  wire        cp0_scause_int  = `SP_TRAP.s_intr;
  wire [4:0]  cp0_scause_code = `SP_TRAP.s_vector[4:0];
  wire [63:0] cp0_sepc        = {`SP_TRAP.sepc_reg[62:0], 1'b0};
  wire        cp0_spp         = `SP_TRAP.spp;
  wire        cp0_sstatus_sie = `SP_TRAP.sie_bit;
  wire        cp0_sstatus_spie= `SP_TRAP.spie;
  wire [63:0] cp0_mtvec       = `SP_TRAP.mtvec_value;   // [0] = MODE (1: vectored)
  wire [63:0] cp0_stvec       = `SP_TRAP.stvec_value;
  wire [63:0] cp0_mideleg     = `SP_TRAP.mideleg_value;

  // --------------------------------------------------------------------------
  // 6-2. 인터럽트 경로 : 원인 -> (PLIC | CLINT) -> sysio flop -> CP0 mip -> RTU -> trap
  //   TB 장치 선(tb/study_tbdev.v) 0/1 = PLIC ID 35/36
  // --------------------------------------------------------------------------
  wire        irq_ext0        = tb.x_soc.x_cpu_sub_system_axi.study_ext_irq[0];
  wire        irq_ext1        = tb.x_soc.x_cpu_sub_system_axi.study_ext_irq[1];
  wire        plic_ip35       = `SP_PLIC.x_plic_kid_busif.kid_busif_pending[35]; // gateway 통과, pending
  wire        plic_ip36       = `SP_PLIC.x_plic_kid_busif.kid_busif_pending[36];
  wire        plic_act35      = `SP_PLIC.x_plic_kid_busif.kid_int_active[35];    // claim 됨, complete 전
  wire        plic_act36      = `SP_PLIC.x_plic_kid_busif.kid_int_active[36];
  wire [9:0]  plic_mclaim     = `SP_PLIC.x_plic_hreg_busif.hart_mclaim_flop[0];  // M claim 을 읽으면 받을 ID
  wire [9:0]  plic_sclaim     = `SP_PLIC.x_plic_hreg_busif.hart_sclaim_flop[0];  // S claim 을 읽으면 받을 ID
  wire        plic_meip       = `SP_CPU_TOP.plic_core0_me_int;   // PLIC -> hart0 M 컨텍스트 요청
  wire        plic_seip       = `SP_CPU_TOP.plic_core0_se_int;   // PLIC -> hart0 S 컨텍스트 요청
  wire        clint_msip      = `SP_CLINT.msip0_reg;             // CLINT MSIP0 (IPI)
  wire        clint_ssip      = `SP_CLINT.ssip0_reg;             // CLINT SSIP0 (C906 확장)
  wire        clint_mtip      = `SP_CPU_TOP.clint_core0_mt_int;  // mtime >= mtimecmp
  // CP0 mip / mie : 비트별. mip.MEIP/MSIP/MTIP 는 위 신호를 sysio 에서 1 사이클 flop 한 값이다
  wire        mip_meip        = `SP_TRAP.meip;
  wire        mip_msip        = `SP_TRAP.msip;
  wire        mip_mtip        = `SP_TRAP.mtip;
  wire        mip_seip        = `SP_TRAP.seip;   // PLIC S 요청 | M 이 쓴 SEIP
  wire        mip_ssip        = `SP_TRAP.ssip;   // CLINT SSIP0 & CLINTEE | M/S 가 쓴 SSIP
  wire        mie_meie        = `SP_TRAP.meie;
  wire        mie_msie        = `SP_TRAP.msie;
  wire        mie_mtie        = `SP_TRAP.mtie;
  wire        mie_seie        = `SP_TRAP.seie;
  wire        mie_ssie        = `SP_TRAP.ssie;
  // RTU : 지금 받아들일 수 있는 인터럽트가 있다 -> 다음에 retire 하는 명령에 붙어서 trap 이 된다
  wire        int_req         = `SP_RTU.x_aq_rtu_int.int_vld;
  wire [4:0]  int_vec         = int_req ? `SP_RTU.x_aq_rtu_int.int_vec[4:0] : 5'd0;
  wire        rt_expt_int     = `SP_CORE.rtu_yy_xx_expt_int;     // 이번 trap 이 인터럽트

  // 인터럽트 원인이 1 이 된 뒤 몇 사이클째인지 (원인이 모두 0 이면 0). trap 순간의 값 = 원인 -> trap 지연
  wire        irq_src         = irq_ext0 | irq_ext1 | clint_msip | clint_ssip | clint_mtip | mip_ssip;
  reg         irq_src_d;
  reg  [15:0] irq_age;
  always @(posedge clk) begin
    irq_src_d <= irq_src;
    if (!irq_src)               irq_age <= 16'd0;
    else if (!irq_src_d)        irq_age <= 16'd1;
    else if (irq_age != 16'hffff) irq_age <= irq_age + 16'd1;
  end

  // 6-2b. WFI 저전력 상태 (aq_cp0_lpmd) 와 인터럽트 플래그 (p5_sys06)
  //   wfi_state : 0 IDLE, 1 WAIT (WFI 를 받아 앞 명령/LSU 가 비기를 기다림), 2 LPMD (잠듦)
  //   wfi_wake  : mip & mie 가 하나라도 1 (mstatus.MIE 와 무관) -> 잠에서 깨는 조건
  wire [1:0]  wfi_state       = `SP_CP0.x_aq_cp0_special.x_aq_cp0_lpmd.cur_state[1:0];
  wire        wfi_in_lpmd     = `SP_CP0.x_aq_cp0_special.x_aq_cp0_lpmd.cpu_in_lpmd;
  wire        wfi_wake        = `SP_CP0.x_aq_cp0_special.x_aq_cp0_lpmd.regs_lpmd_int_vld;
  //   int_flag : INT_FLAG_ADDR(common/study.h) 로의 store 를 LSU DC 단계에서 감지한 값 (메모리 그림자)
  reg  [31:0] int_flag;
  initial int_flag = 32'd0;
  always @(posedge clk)
    if (`SP_LSU.x_aq_lsu_dc.dc_stb_req && `SP_LSU.x_aq_lsu_dc.dc_stb_pa[39:2] == 38'h1FFE0 >> 2) begin
      if (`SP_LSU.x_aq_lsu_dc.dc_stb_src2_depd)
        $display("[probe] cycle %0d: WARNING int_flag store data not ready at DC", cycle);
      int_flag <= `SP_LSU.x_aq_lsu_dc.dc_stb_data[31:0];
      $display("[flag] cycle %0d: int_flag <- %0d", cycle, `SP_LSU.x_aq_lsu_dc.dc_stb_data[31:0]);
    end
  // WFI 진입/깨어남 로그
  reg  [1:0]  wfi_state_d;
  reg  [31:0] wfi_sleep_cyc;
  initial wfi_state_d = 2'd0;
  always @(posedge clk) begin
    wfi_state_d <= wfi_state;
    if (wfi_state == 2'd2 && wfi_state_d != 2'd2) begin
      wfi_sleep_cyc <= cycle;
      $display("[wfi] cycle %0d: sleep (LPMD), int_flag = %0d", cycle, int_flag);
    end
    if (wfi_state != 2'd2 && wfi_state_d == 2'd2)
      $display("[wfi] cycle %0d: wake up after %0d cycles", cycle, cycle - wfi_sleep_cyc);
  end

  // 6-3. 인터럽트 trap 로그. trap(rt_expt) 다음 사이클에 CSR 이 갱신되고 RTU 가 IFU 를 trap 벡터로
  //      redirect 한다(rt_redirect_pc). 그때 한 줄 출력하고, 그 주소의 명령이 retire 하면 진입 사이클을 출력한다
  reg         itrap_d, itrap_wait;
  reg  [31:0] itrap_cyc, itrap_cnt;
  reg  [15:0] itrap_age;
  reg  [1:0]  itrap_priv;
  reg  [39:0] itrap_tvec, itrap_rtpc;
  initial begin itrap_d = 0; itrap_wait = 0; itrap_cnt = 0; end
  always @(posedge clk) begin
    itrap_d <= rt_expt && rt_expt_int;
    if (rt_expt && rt_expt_int) begin
      itrap_cyc  <= cycle;
      itrap_age  <= irq_age;
      itrap_priv <= cp0_priv;
      itrap_rtpc <= rt_pc;
    end
    if (itrap_d) begin
      itrap_cnt  <= itrap_cnt + 1;
      itrap_tvec <= rt_redirect_pc;
      itrap_wait <= 1'b1;
      $display("[irq] #%0d cycle %0d: %s-mode interrupt cause %0d on retire of pc %h, priv %0d -> %0d, %0sepc = %h, PC -> %h (source up %0d cycles before)",
        itrap_cnt + 1, itrap_cyc, cp0_priv == 2'b11 ? "M" : "S",
        cp0_priv == 2'b11 ? cp0_mcause_code : cp0_scause_code, itrap_rtpc, itrap_priv, cp0_priv,
        cp0_priv == 2'b11 ? "m" : "s", cp0_priv == 2'b11 ? cp0_mepc[39:0] : cp0_sepc[39:0],
        rt_redirect_pc, itrap_age);
    end
    if (itrap_wait && !itrap_d && rt_vld && rt_pc == itrap_tvec) begin
      itrap_wait <= 1'b0;
      $display("@@ irq%0d_src_to_trap_cycles = %0d", itrap_cnt, itrap_age);
      $display("@@ irq%0d_trap_to_vector_retire_cycles = %0d", itrap_cnt, cycle - itrap_cyc);
    end
  end

  // --------------------------------------------------------------------------
  // 6-1. 콘솔 채널 : "csrw mscratch, ch" 를 감지해 문자를 출력한다.
  //  (smart_run 의 sysmap 에서 UART 주소 0x10015000 은 cacheable 영역이라
  //   sw 가 D-Cache 에만 머물고 AXI 로 나가지 않는다. 그래서 CSR 쓰기를 쓴다.)
  // --------------------------------------------------------------------------
  wire        con_wen         = `SP_TRAP.mscratch_local_en;
  wire [63:0] con_val         = `SP_TRAP.mscratch[63:0];
  reg         con_wen_d;
  initial con_wen_d = 1'b0;
  always @(posedge clk) begin
    con_wen_d <= con_wen && rst_b;     // 리셋 전 임의 초기값으로 문자가 찍히지 않게
    if (con_wen_d) begin
      $write("%c", con_val[7:0]);
      $fflush;
    end
  end

  // --------------------------------------------------------------------------
  // 7. AXI master (BIU <-> SoC)
  // --------------------------------------------------------------------------
  wire        bus_arvalid     = tb.x_soc.biu_pad_arvalid;
  wire        bus_arready     = tb.x_soc.pad_biu_arready;
  wire [39:0] bus_araddr      = tb.x_soc.biu_pad_araddr[39:0];
  wire [7:0]  bus_arlen       = tb.x_soc.biu_pad_arlen[7:0];
  wire        bus_rvalid      = tb.x_soc.pad_biu_rvalid;
  wire        bus_rlast       = tb.x_soc.pad_biu_rlast;
  wire        bus_awvalid     = tb.x_soc.biu_pad_awvalid;
  wire [39:0] bus_awaddr      = tb.x_soc.biu_pad_awaddr[39:0];
  wire        bus_wvalid      = tb.x_soc.biu_pad_wvalid;
  wire        bus_bvalid      = tb.x_soc.pad_biu_bvalid;

  // --------------------------------------------------------------------------
  // 8. PC -> 디스어셈블리 ASCII (GTKWave 에서 Data Format = ASCII 로 표시)
  // --------------------------------------------------------------------------
  localparam ASM_W   = 8*40;           // 40 글자
  localparam ASM_N   = 16384;          // 0x0000 ~ 0x7FFF (halfword 단위 인덱스)
  reg [ASM_W-1:0] asm_rom [0:ASM_N-1];
  reg [8*256-1:0] asm_file;
  integer k;
  initial begin
    for (k = 0; k < ASM_N; k = k + 1) asm_rom[k] = {ASM_W{1'b0}};
    if ($value$plusargs("asm=%s", asm_file)) $readmemh(asm_file, asm_rom);
  end
  function [ASM_W-1:0] asm_of(input [39:0] pc);
    asm_of = (pc < 40'h8000) ? asm_rom[pc[14:1]] : "(out of text)";
  endfunction

  wire [ASM_W-1:0] asm_if  = fe_if_grant ? asm_of(fe_if_pc) : "";
  wire [ASM_W-1:0] asm_ip  = fe_ip_vld0  ? asm_of(fe_ip_pc) : "";
  wire [ASM_W-1:0] asm_ex1 = ex1_vld     ? asm_of(ex1_pc)   : "";
  wire [ASM_W-1:0] asm_rt  = rt_vld      ? asm_of(rt_pc)    : "";

  // --------------------------------------------------------------------------
  // 9. VCD 덤프 제어
  // --------------------------------------------------------------------------
  reg [8*256-1:0] vcd_file;
  integer from_mark, to_mark;
  reg     dumping;
  initial begin
    from_mark = -1; to_mark = -1; dumping = 1'b0;
    if (!$value$plusargs("vcd_from_mark=%d", from_mark)) from_mark = -1;
    if (!$value$plusargs("vcd_to_mark=%d",   to_mark))   to_mark   = -1;
    if ($value$plusargs("vcd=%s", vcd_file)) begin
      $dumpfile(vcd_file);
      $dumpvars(1, study_probe);
      if ($test$plusargs("vcd_full")) $dumpvars(0, `SP_CORE);
      dumping = 1'b1;
      if (from_mark >= 0) begin
        #1 $dumpoff;
        dumping = 1'b0;
      end
    end
  end
  always @(posedge clk) begin
    if (from_mark >= 0 && !dumping && mark == from_mark) begin
      $dumpon;  dumping <= 1'b1;
    end
    if (to_mark >= 0 && dumping && mark == to_mark) begin
      $dumpoff; dumping <= 1'b0;
    end
  end

  // --------------------------------------------------------------------------
  // 10. 사이클 trace 로그 (tools/pipeview.py 가 사람이 읽는 표로 변환)
  //  필드: cyc mark | IF | IP | IBUF | ID | EX1 | BJU | LSU | RT | 이벤트
  // --------------------------------------------------------------------------
  integer         tfd;
  reg [8*256-1:0] trace_file;
  reg             trace_all;
  initial begin
    tfd = 0;
    trace_all = $test$plusargs("trace_all");
    if ($value$plusargs("trace=%s", trace_file)) begin
      tfd = $fopen(trace_file, "w");
      $fdisplay(tfd, "# cyc mark if_g if_pc btb_hit btb_redir ip_v0 ip_v1 ip_pc ip_taken ip_redir ip_redir_pc ip_curflw ibuf id_v id_inst pipedown stall raw waw ex1st cp0st ex1_v ex1_eu ex1_pc br_v br_taken bht_misp jalr_misp ras_misp iu_redir iu_redir_pc mul_wb div_busy ag_v ag_va dc_v dc_ld dc_st dc_hit dc_miss stb_fwd ldv rt_v rt_pc flush rt_redir rt_redir_pc expt priv ghr bht_pred ras_ptr stb_part ic_miss");
    end
  end
  always @(posedge clk) begin
    if (tfd != 0 && rst_b && (trace_all || mark != 0)) begin
      $fdisplay(tfd, "%0d %0d %b %h %b %b %b %b %h %b %b %h %b %0d %b %h %b %b %b %b %b %b %b %b %h %b %b %b %b %b %b %h %b %b %b %h %b %b %b %b %b %b %b %b %h %b %b %h %b %0d %h %b %h %b %b",
        cycle, mark, fe_if_grant, fe_if_pc, fe_btb_hit, fe_btb_redirect,
        fe_ip_vld0, fe_ip_vld1, fe_ip_pc, fe_ip_br_taken, fe_ip_redirect, fe_ip_redir_pc, fe_ip_curflw,
        fe_ibuf_num, id_vld, id_inst, id_pipedown, id_stall, id_stall_raw, id_stall_waw, id_stall_ex1, id_stall_cp0,
        ex1_vld, ex1_eu, ex1_pc,
        bju_br_vld, bju_br_taken, bju_bht_mispred, bju_jalr_mispred, bju_ras_mispred, iu_redirect, iu_redirect_pc,
        mul_wb, div_busy,
        lsu_ag_vld, lsu_ag_va, lsu_dc_vld, lsu_dc_ld, lsu_dc_st, lsu_dc_hit, lsu_dc_miss, lsu_stb_fwd, lsu_ld_data_vld,
        rt_vld, rt_pc, rt_flush, rt_redirect, rt_redirect_pc, rt_expt, cp0_priv,
        fe_bht_ghr, fe_bht_pred, fe_ras_ptr, lsu_stb_part, fe_ic_miss);
    end
  end

endmodule
