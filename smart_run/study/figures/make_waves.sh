#!/bin/bash
# 문서에 들어가는 GTKWave 파형 캡처를 다시 만든다.
#   전제: unit_tests 에서 make all 로 out/<test>/*.vcd 가 만들어져 있어야 한다.
#   (cycle 번호는 Verilator seed 7 실행 기준. 테스트를 고치면 범위를 다시 잡아야 한다)
set -e
cd "$(dirname "$0")/../unit_tests"
S="python3 tools/wave_snap.py"
FIG=../figures

$S out/p2_fe02_bp_loop --from-cycle 4496 --to-cycle 4520 --pad 0 --height 560 \
  --signals "clk,cycle,-Front-End,fe_if_grant,asm_if,fe_btb_hit,fe_btb_redirect,asm_ip,fe_ip_redirect,-Execute / Retire,asm_ex1,bju_br_vld,bju_br_taken,iu_redirect,asm_rt" \
  -o $FIG/wave_bp_btb_on.png
$S out/p2_fe02_bp_loop --from-cycle 8400 --to-cycle 8424 --pad 0 --height 560 \
  --signals "clk,cycle,-Front-End,fe_if_grant,asm_if,fe_btb_hit,fe_btb_redirect,asm_ip,fe_ip_redirect,-Execute / Retire,asm_ex1,bju_br_vld,bju_br_taken,iu_redirect,asm_rt" \
  -o $FIG/wave_bp_btb_off.png
$S out/p2_fe02_bp_loop --from-cycle 12400 --to-cycle 12424 --pad 0 --height 600 \
  --signals "clk,cycle,-Front-End,asm_if,asm_ip,fe_ip_redirect,fe_bht_pred,-Execute / Retire,asm_ex1,bju_br_vld,bju_br_taken,bju_bht_mispred,iu_redirect,iu_redirect_pc,asm_rt" \
  -o $FIG/wave_bp_mispredict.png
$S out/p2_fe04_ras_jalr --from-cycle 4012 --to-cycle 4042 --pad 0 --height 640 \
  --signals "clk,cycle,-Front-End,asm_ip,fe_ras_push,fe_ras_pop,fe_ras_ptr,fe_ras_ptr_bju,fe_ip_curflw,-Execute / Retire,asm_ex1,bju_bht_mispred,bju_ras_mispred,iu_redirect,iu_redirect_pc,rt_flush,asm_rt" \
  -o $FIG/wave_ras_overflow.png
$S out/p3_be01_hazard --from-cycle 3788 --to-cycle 3808 --pad 0 --height 600 \
  --signals "clk,cycle,-Decode,id_vld,id_pipedown,id_stall,id_stall_raw,-Execute / LSU,asm_ex1,lsu_ag_vld,lsu_dc_vld,lsu_dc_hit,lsu_ld_data_vld,-Retire,wb0_vld,wb0_reg,wb1_vld,wb1_reg,asm_rt" \
  -o $FIG/wave_load_use.png
$S out/p3_be04_trap --from-cycle 2733 --to-cycle 2753 --pad 0 --height 640 \
  --signals "clk,cycle,-Execute / Retire,asm_ex1,asm_rt,rt_expt,rt_flush,rt_redirect,rt_redirect_pc,-CP0,cp0_priv,cp0_mcause_int,cp0_mcause_code,cp0_mepc,cp0_mstatus_mie,cp0_mstatus_mpie" \
  -o $FIG/wave_trap_ecall.png
$S out/p4_mem01_dcache --mark 1 --pad 2 --height 600 \
  --signals "clk,cycle,-LSU,asm_ex1,lsu_ag_vld,lsu_ag_va,lsu_dc_vld,lsu_dc_miss,lsu_ld_data_vld,-AXI,bus_arvalid,bus_arready,ic_arvalid,ic_arready,bus_araddr,bus_arlen,bus_rvalid,bus_rlast,-Retire,asm_rt" \
  -o $FIG/wave_dcache_miss.png
$S out/p4_mem04_sv39 --mark 1 --pad 2 --height 560 \
  --signals "clk,cycle,-LSU / PTW,asm_ex1,lsu_ag_va,lsu_dc_vld,lsu_dc_pa,lsu_dc_miss,lsu_ld_data_vld,-AXI,bus_arvalid,bus_araddr,-Retire,asm_rt,cp0_priv" \
  -o $FIG/wave_sv39_ptw.png
$S out/p5_sys01_priv_deleg --from-cycle 2735 --to-cycle 2966 --pad 0 --height 560 \
  --signals "clk,cycle,mark,-Retire,asm_rt,rt_expt,rt_redirect,rt_redirect_pc,-CP0,cp0_priv,cp0_mcause_code,cp0_scause_code,cp0_mstatus_mpp,cp0_spp" \
  -o $FIG/wave_priv_deleg.png
$S out/p5_sys02_timer_irq --from-cycle 4436 --to-cycle 4461 --pad 0 --height 520 \
  --signals "clk,cycle,-Retire,asm_rt,rt_expt,rt_redirect,rt_redirect_pc,-CP0,cp0_priv,cp0_mstatus_mie,cp0_mcause_int,cp0_mcause_code,cp0_mepc" \
  -o $FIG/wave_timer_irq.png
# Phase 5 6 절 : 인터럽트 진입 해부 (p5_sys04_ext_irq, p5_sys05_ipi)
$S out/p5_sys04_ext_irq --from-cycle 2830 --to-cycle 2870 --pad 0 --height 820 \
  --signals "clk,cycle,-Source / PLIC,irq_ext0,plic_ip35,plic_mclaim,plic_meip,-CP0 mip / mie / RTU,mip_meip,mie_meie,cp0_mstatus_mie,int_req,int_vec,-Retire / PC,asm_rt,rt_expt,rt_redirect,rt_redirect_pc,fe_if_pc,-Trap CSR (M),cp0_priv,cp0_mcause_int,cp0_mcause_code,cp0_mepc,cp0_mstatus_mpie,cp0_mstatus_mpp" \
  -o $FIG/wave_irq_m_entry.png
$S out/p5_sys04_ext_irq --from-cycle 7655 --to-cycle 7702 --pad 0 --height 820 \
  --signals "clk,cycle,-Source / PLIC,irq_ext0,plic_ip35,plic_sclaim,plic_seip,-CP0 mip / mie / RTU,mip_seip,mie_seie,cp0_sstatus_sie,int_req,int_vec,-Retire / PC,asm_rt,rt_vld,rt_expt,rt_redirect,rt_redirect_pc,-Trap CSR (S),cp0_priv,cp0_scause_int,cp0_scause_code,cp0_sepc,cp0_sstatus_spie,cp0_spp" \
  -o $FIG/wave_irq_s_entry.png
$S out/p5_sys04_ext_irq --from-cycle 3138 --to-cycle 3168 --pad 0 --height 640 \
  --signals "clk,cycle,-Handler,asm_rt,-PLIC,irq_ext0,plic_ip35,plic_act35,plic_mclaim,plic_meip,mip_meip,-Return,rt_redirect,rt_redirect_pc,cp0_priv,cp0_mstatus_mie,cp0_mstatus_mpie" \
  -o $FIG/wave_irq_claim_complete.png
$S out/p5_sys05_ipi --from-cycle 5990 --to-cycle 6076 --pad 0 --height 720 \
  --signals "clk,cycle,-CLINT / mip,clint_msip,mip_msip,mip_ssip,int_req,int_vec,-Retire / PC,asm_rt,rt_expt,rt_redirect_pc,-Trap CSR,cp0_priv,cp0_mcause_code,cp0_mepc,cp0_scause_code,cp0_sepc" \
  -o $FIG/wave_ipi_sbi.png
# Phase 5 6.7 절 : while (!int_flag) { wfi; } (p5_sys06_wfi_flag MARK 2)
$S out/p5_sys06_wfi_flag --from-cycle 5975 --to-cycle 6700 --pad 0 --width 1600 --height 600 \
  --signals "cycle,mark,-Flag / WFI,int_flag,wfi_state,wfi_in_lpmd,wfi_wake,-Sources,irq_ext1,irq_ext0,plic_mclaim,mip_meip,-Retire / Trap,rt_vld,rt_expt,cp0_mepc" \
  -o $FIG/wave_wfi_loop.png
$S out/p5_sys06_wfi_flag --from-cycle 6580 --to-cycle 6630 --pad 0 --height 640 \
  --signals "clk,cycle,-Source / mip,irq_ext0,plic_mclaim,mip_meip,mie_meie,cp0_mstatus_mie,-WFI,wfi_state,wfi_in_lpmd,wfi_wake,int_req,-Retire / PC,asm_rt,rt_expt,rt_redirect,rt_redirect_pc,cp0_mepc,cp0_mcause_code" \
  -o $FIG/wave_wfi_wake.png
$S out/p5_sys06_wfi_flag --from-cycle 6656 --to-cycle 6692 --pad 0 --height 600 \
  --signals "clk,cycle,-Handler / Flag,asm_rt,lsu_dc_st,lsu_dc_pa,int_flag,irq_ext0,plic_act35,-mret -> loop,rt_redirect,rt_redirect_pc,cp0_mstatus_mie,lsu_dc_ld,mark" \
  -o $FIG/wave_wfi_exit.png
# Phase 8 2 절 : AXI / AHB / APB 실제 핸드셰이크 (p8_bus01_amba)
$S out/p8_bus01_amba --from-cycle 2675 --to-cycle 2688 --pad 0 --height 600 \
  --signals "clk,cycle,-AR (BIU ↔ axi_fifo),bus_arvalid,bus_arready,bus_araddr,bus_arlen,bus_arburst,-AR (axi_fifo → interconnect),ic_arvalid,ic_arready,-R (읽기 데이터),bus_rvalid,bus_rready,bus_rdata_lo,bus_rlast,bus_rresp" \
  -o $FIG/wave_axi_read_burst.png
$S out/p8_bus01_amba --from-cycle 2702 --to-cycle 2716 --pad 0 --height 700 \
  --signals "clk,cycle,-AW,bus_awvalid,bus_awready,bus_awaddr,bus_awlen,-W,bus_wvalid,bus_wready,bus_wdata_lo,bus_wstrb,bus_wlast,-B,bus_bvalid,bus_bready,bus_bresp,-AR / R,bus_arvalid,bus_arready,ic_arvalid,bus_rvalid,bus_rdata_lo" \
  -o $FIG/wave_axi_write.png
$S out/p8_bus01_amba --from-cycle 2766 --to-cycle 2779 --pad 0 --height 720 \
  --signals "clk,cycle,-AXI,bus_awvalid,bus_awready,bus_wvalid,bus_wready,bus_bvalid,-AHB,ahb_htrans,ahb_haddr,ahb_hwrite,ahb_hsize,ahb_hwdata_lo,ahb_hready,ahb_hsel_apb,-APB,apb_psel,apb_penable,apb_paddr,apb_pwrite,apb_pwdata" \
  -o $FIG/wave_ahb_apb_write.png
$S out/p8_bus01_amba --from-cycle 2945 --to-cycle 2956 --pad 0 --height 700 \
  --signals "clk,cycle,-AXI,ic_arvalid,ic_arready,bus_rvalid,bus_rdata_lo,-AHB,ahb_htrans,ahb_hwrite,ahb_hsize,ahb_hready,ahb_hrdata_lo,ahb_hsel_apb,-APB,apb_psel,apb_penable,apb_pwrite,apb_prdata_bdly" \
  -o $FIG/wave_ahb_apb_read.png
$S out/p8_bus01_amba --from-cycle 2988 --to-cycle 3022 --pad 0 --height 560 \
  --signals "clk,cycle,-CPU 내부 APB (BIU apbif),capb_psel_plic,capb_penable,capb_paddr,capb_pwrite,capb_pwdata,capb_prdata_plic,-AXI (조용함),bus_arvalid,bus_awvalid,-Retire,asm_rt" \
  -o $FIG/wave_capb_plic.png
# Phase 4 2.7 절 : dirty 라인 교체 write-back, th.dcache.cva (p4_mem05_writeback)
$S out/p4_mem05_writeback --from-cycle 3566 --to-cycle 3580 --pad 0 --height 620 \
  --signals "clk,cycle,-VB write-back (AXI 쓰기),bus_awvalid,bus_awready,bus_awaddr,bus_awlen,bus_awburst,bus_wvalid,bus_wready,bus_wlast,bus_bvalid,-Refill (AXI 읽기),bus_arvalid,bus_araddr,ic_arvalid,ic_arready" \
  -o $FIG/wave_wb_evict.png
$S out/p4_mem05_writeback --from-cycle 5026 --to-cycle 5060 --pad 0 --height 520 \
  --signals "clk,cycle,mark,-Retire,asm_rt,-AXI 쓰기,bus_awvalid,bus_awaddr,bus_awlen,bus_wvalid,bus_wlast,bus_bvalid" \
  -o $FIG/wave_wb_cva.png
# Phase 6 8.0 절 : FPU latency, FDSU, FS (p6_fp01_latency)
$S out/p6_fp01_latency --from-cycle 3298 --to-cycle 3322 --pad 0 --height 460 \
  --signals "clk,cycle,-Execute,asm_ex1,fp_ex1_stall,-FP write-back,fp_wb_vld,fp_wb_reg,-Retire,asm_rt" -o $FIG/wave_fp_chain.png
$S out/p6_fp01_latency --from-cycle 3768 --to-cycle 3794 --pad 0 --height 460 \
  --signals "clk,cycle,-Execute,asm_ex1,fp_ex1_stall,-FP write-back,fp_wb_vld,fp_wb_reg,-Retire,asm_rt" -o $FIG/wave_fp_indep.png
$S out/p6_fp01_latency --from-cycle 5088 --to-cycle 5130 --pad 0 --width 1600 --height 460 \
  --signals "clk,cycle,-Execute,asm_ex1,fp_fdsu_busy,-FP write-back,fp_wb_vld,fp_wb_reg,-Retire,asm_rt" -o $FIG/wave_fp_fdiv.png
$S out/p6_fp01_latency --from-cycle 8080 --to-cycle 8100 --pad 0 --height 460 \
  --signals "clk,cycle,-Retire,asm_rt,rt_expt,rt_redirect,rt_redirect_pc,-CP0,cp0_mstatus_fs,cp0_mcause_code,cp0_mepc" -o $FIG/wave_fp_fs_off.png
# Phase 7 4.5 절 : 하드웨어 trigger (p7_dbg01_trigger)
$S out/p7_dbg01_trigger --from-cycle 3600 --to-cycle 3628 --pad 0 --height 480 \
  --signals "clk,cycle,mark,-Fetch,fe_if_pc,-Retire,asm_rt,rt_expt,rt_redirect,rt_redirect_pc,-Trap,cp0_mcause_code,cp0_mepc" -o $FIG/wave_dbg_exec_bp.png
$S out/p7_dbg01_trigger --from-cycle 4438 --to-cycle 4458 --pad 0 --height 460 \
  --signals "clk,cycle,mark,-Execute,asm_ex1,-Retire,asm_rt,rt_expt,rt_redirect_pc,-Trap,cp0_mcause_code,cp0_mepc" -o $FIG/wave_dbg_store_wp.png
# Phase 5 6.8 절 : 우선순위와 중첩 (p5_sys07_irq_nest)
$S out/p5_sys07_irq_nest --from-cycle 3020 --to-cycle 3560 --pad 0 --width 1600 --height 560 \
  --signals "cycle,mark,-Pending,mip_meip,mip_msip,mip_mtip,cp0_mstatus_mie,-RTU,int_req,int_vec,rt_expt,-Trap CSR,cp0_mcause_code,cp0_mepc" -o $FIG/wave_irq_prio.png
$S out/p5_sys07_irq_nest --from-cycle 3430 --to-cycle 3452 --pad 0 --height 480 \
  --signals "clk,cycle,-Retire,asm_rt,rt_expt,rt_redirect,rt_redirect_pc,-Interrupt,int_req,int_vec,-Trap CSR,cp0_mcause_code,cp0_mepc" -o $FIG/wave_irq_tailchain.png
$S out/p5_sys07_irq_nest --from-cycle 4680 --to-cycle 4900 --pad 0 --width 1600 --height 600 \
  --signals "cycle,mark,-Pending,mip_mtip,mip_msip,cp0_mstatus_mie,-RTU,int_req,int_vec,rt_expt,-Trap CSR,cp0_mcause_code,cp0_mepc,-Retire,asm_rt" -o $FIG/wave_irq_nest.png
# Phase 2 2.5.1 절 : RVC 밀도와 분기 목표 정렬 (p2_fe05_rvc_density)
$S out/p2_fe05_rvc_density --from-cycle 8480 --to-cycle 8497 --pad 0 --height 460 \
  --signals "clk,cycle,-Front-End,fe_if_pc,fe_btb_redirect,fe_ip_redirect,asm_ip,-Retire,asm_rt" -o $FIG/wave_rvc_loop_aligned.png
$S out/p2_fe05_rvc_density --from-cycle 9152 --to-cycle 9169 --pad 0 --height 460 \
  --signals "clk,cycle,-Front-End,fe_if_pc,fe_btb_redirect,fe_ip_redirect,asm_ip,-Retire,asm_rt" -o $FIG/wave_rvc_loop_misaligned.png
# p3_be06: wb0 중재 - ALU 가 EX1 을 계속 차지하면 MUL(EX3) 과 DIV(WFWB) 가 결과를 못 쓴다
$S out/p3_be06_exec_mix --from-cycle 7842 --to-cycle 7864 --pad 0 --height 620 \
  --signals "clk,cycle,-Execute / Retire,asm_ex1,ex1_cmplt,asm_rt,-MUL,mul_ex2_vld,mul_ex3_vld,mul_wb,mul_grant,mul_ex3_stall,fwd1_vld,-Write-back,wb0_vld,wb0_reg,-ID,id_stall_raw" \
  -o $FIG/wave_wb_arb_mul.png
$S out/p3_be06_exec_mix --from-cycle 6173 --to-cycle 6195 --pad 0 --height 600 \
  --signals "clk,cycle,-Execute / Retire,asm_ex1,ex1_cmplt,asm_rt,-DIV,div_state,div_wb,div_grant,-Write-back,wb0_vld,wb0_reg,-ID,id_stall_raw" \
  -o $FIG/wave_wb_arb_div.png
