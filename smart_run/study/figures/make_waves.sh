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
  --signals "clk,cycle,-LSU,asm_ex1,lsu_ag_vld,lsu_ag_va,lsu_dc_vld,lsu_dc_miss,lsu_ld_data_vld,-AXI,bus_arvalid,bus_arready,bus_araddr,bus_arlen,bus_rvalid,bus_rlast,-Retire,asm_rt" \
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
