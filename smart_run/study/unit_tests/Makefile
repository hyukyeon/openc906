# ============================================================================
# OpenC906 학습용 유닛 테스트
#
#   make sim                 : RTL + tb + study_probe 빌드 (Verilator, 최초 1회 약 3~4분)
#   make run T=<test>        : 테스트 하나 빌드/실행 -> out/<test>/ 에 VCD, trace, pipeview, 결과
#                              (objdump, console.log 는 tests/<test>/ 의 소스 옆에도 복사)
#   make all                 : tests/*/*.S 전부 실행 후 결과 요약(out/RESULTS.md)
#   make list                : 테스트 목록
#   make wave T=<test>       : GTKWave 로 결과 열기 (테스트별 gtkw 세이브 파일 사용)
#   make web                 : 브라우저 파형 뷰어(Surfer) 시작 -> tailnet 의 https://<host>:10000/
#   make web-stop            : 브라우저 파형 뷰어 중지
#   make site                : 서버 없이 열리는 정적 사이트로 내보내기 -> $(SITE) (GitHub Pages 저장소)
#   make clean
#
# 옵션
#   SIM=iverilog             : iverilog 로 실행 (원본 smart_run 과 같은 시뮬레이터, 매우 느림: 테스트당 수 분~수십 분)
#   FULL=1                   : aq_core 전체 신호를 VCD 에 덤프 (별도 빌드, 용량 큼)
#   PATCH=<name>             : patches/<name>/*.v 로 같은 이름의 RTL 파일을 교체해서 빌드 (실험용)
# ============================================================================

UT_DIR        := $(abspath .)
SMART_RUN     := $(abspath ../..)
export CODE_BASE_PATH ?= $(abspath $(SMART_RUN)/../C906_RTL_FACTORY)

CROSS         ?= riscv64-unknown-elf-
CC            := $(CROSS)gcc
OBJDUMP       := $(CROSS)objdump
OBJCOPY       := $(CROSS)objcopy
SREC2VMEM     := $(SMART_RUN)/tests/bin/Srec2vmem
PYTHON        ?= python3

# 학습 테스트는 표준 RV64GC 만 사용한다 (XThead 확장 미사용)
MARCH         := -march=rv64imafdc_zicsr_zifencei -mabi=lp64d
CFLAGS        := $(MARCH) -nostdlib -nostartfiles -static -mcmodel=medany -I$(UT_DIR)/common

# 테스트 하나 = 폴더 하나 : tests/<test>/<test>.S (+ 실행 후 복사되는 <test>.objdump, console.log)
TESTS         := $(sort $(notdir $(patsubst %/,%,$(dir $(wildcard tests/*/*.S)))))

SIM           ?= verilator
PATCH         ?=
FULL          ?=
SFX           := $(if $(PATCH),_$(PATCH))$(if $(FULL),_full)
RTL_FL        := build/C906_rtl$(if $(PATCH),_$(PATCH)).fl
VSIM          := build/verilator$(SFX)/obj/Vsim
VVP           := build/study$(SFX).vvp
SIM_BIN       := $(if $(filter iverilog,$(SIM)),$(VVP),$(VSIM))

.PHONY: sim run all list wave web web-stop site clean
.DEFAULT_GOAL := list

list:
	@echo "tests:"; for t in $(TESTS); do echo "  $$t"; done

# ---------------------------------------------------------------- filelists
build/filelists.stamp:
	@mkdir -p build
	@sed 's#\.\./logical#$(SMART_RUN)/logical#g' $(SMART_RUN)/logical/filelists/smart.fl > build/smart.fl
	@sed 's#\.\./logical#$(SMART_RUN)/logical#g' $(SMART_RUN)/logical/filelists/tb.fl    > build/tb.fl
	@cat build/smart.fl build/tb.fl | grep -E '^(\+|-y|/[^*])' > build/soc_tb.fl
	@touch $@

$(RTL_FL): build/filelists.stamp
	@cp $(CODE_BASE_PATH)/gen_rtl/filelists/C906_asic_rtl.fl $@
	@if [ -n "$(PATCH)" ]; then \
	  for f in patches/$(PATCH)/*.v; do \
	    b=$$(basename $$f); \
	    sed -i "s#^.*/$$b\$$#$(UT_DIR)/$$f#" $@; \
	    echo "  [patch] $$b -> $$f"; \
	  done; fi

# ---------------------------------------------------------------- Verilator
# - tb.v 의 livelock 검사(cycle_count % 50000)는 리셋 전 X 값에 의존한다.
#   Verilator 는 X 를 0 으로 두면 첫 사이클에 FAIL 하므로 --x-initial unique + 랜덤 초기화로 실행한다.
VL_FLAGS := --binary --timing -j 4 --top-module sim_top -o Vsim \
  -Wno-fatal -Wno-lint -Wno-style -Wno-MULTIDRIVEN -Wno-UNOPTFLAT -Wno-COMBDLY -Wno-BLKANDNBLK \
  --x-initial unique --x-assign unique +define+NO_DUMP +define+IVERILOG_SIM \
  --trace $(if $(FULL),,--trace-depth 2)

# tb/soc_overlay/*.v : smart_run/logical 의 같은 이름 SoC 파일 대신 쓰는 학습용 사본 (-y 라이브러리보다 우선)
TB_FILES := $(wildcard tb/soc_overlay/*.v) tb/study_tbdev.v tb/study_probe.v

$(VSIM): $(RTL_FL) $(TB_FILES) tb/sim_top.v $(wildcard patches/$(PATCH)/*.v)
	@echo "  [verilator] building $@ (3~4 min) ..."
	@mkdir -p $(dir $@)
	@verilator $(VL_FLAGS) -Mdir $(dir $@) \
	  -f $(RTL_FL) -f $(CODE_BASE_PATH)/gen_rtl/filelists/tdt_dmi_top_rtl.fl -f build/soc_tb.fl \
	  $(TB_FILES) tb/sim_top.v > $(dir $@)/../build.log 2>&1 \
	  || (tail -30 $(dir $@)/../build.log; exit 1)

# ---------------------------------------------------------------- iverilog
$(VVP): $(RTL_FL) $(TB_FILES)
	@echo "  [iverilog] compile $@"
	@iverilog -o $@ -Diverilog=1 -g2012 -DIVERILOG_SIM -DNO_DUMP \
	  -f $(RTL_FL) -f $(CODE_BASE_PATH)/gen_rtl/filelists/tdt_dmi_top_rtl.fl \
	  -c build/smart.fl -c build/tb.fl $(TB_FILES)

sim: $(SIM_BIN)

# ---------------------------------------------------------------- one test
OUT           = out/$(T)$(SFX)
SRC           = tests/$(T)/$(T).S
# 기본 빌드(Verilator, PATCH/FULL 없음) 결과의 텍스트 파일은 소스 옆에도 복사한다 (git 에 함께 올라가는 사본)
KEEP_TEXT     = $(if $(SFX)$(filter iverilog,$(SIM)),,1)
PROBE_SCOPE   = $(if $(filter iverilog,$(SIM)),study_probe,TOP.sim_top.study_probe)
RUN_ARGS      = +vcd=$(T).vcd +asm=asm_rom.hex +trace=trace.log
ifeq ($(SIM),iverilog)
RUN_CMD       = vvp -n $(UT_DIR)/$(VVP) $(RUN_ARGS) $(if $(FULL),+vcd_full)
else
RUN_CMD       = $(UT_DIR)/$(VSIM) +verilator+rand+reset+2 +verilator+seed+7 $(RUN_ARGS)
endif

run: $(SIM_BIN)
ifeq ($(T),)
	$(error T=<test> 를 지정하세요. 목록: make list)
endif
	@rm -rf $(OUT) && mkdir -p $(OUT)
	@$(CC) $(CFLAGS) -T common/linker.ld common/crt0.S common/lib.S $(SRC) -o $(OUT)/$(T).elf
	@$(OBJDUMP) -d $(OUT)/$(T).elf > $(OUT)/$(T).objdump
	@$(OBJCOPY) -O srec $(OUT)/$(T).elf $(OUT)/inst.srec -j .text -j .rodata
	@$(OBJCOPY) -O srec $(OUT)/$(T).elf $(OUT)/data.srec -j .data -j .bss
	@cd $(OUT) && $(SREC2VMEM) inst.srec inst.pat >/dev/null && $(SREC2VMEM) data.srec data.pat >/dev/null
	@$(PYTHON) tools/mk_asm_rom.py $(OUT)/$(T).objdump $(OUT)/asm_rom.hex
	@$(PYTHON) tools/mk_gtkw.py $(SRC) $(OUT)/$(T).vcd $(OUT)/$(T).gtkw $(PROBE_SCOPE)
	@cd $(OUT) && $(RUN_CMD) > console.log 2>&1; true
	@grep -q "TEST PASS" $(OUT)/run_case.report 2>/dev/null \
	  && echo "  [PASS] $(T)" || (echo "  [FAIL] $(T)  (see $(OUT)/console.log)"; tail -8 $(OUT)/console.log)
	@$(PYTHON) tools/pipeview.py $(OUT) > /dev/null
	@grep "^@@" $(OUT)/console.log | sed 's/^@@ */    /' || true
	@$(if $(KEEP_TEXT),cp $(OUT)/$(T).objdump $(OUT)/console.log tests/$(T)/)

# ---------------------------------------------------------------- all tests
all: $(SIM_BIN)
	@for t in $(TESTS); do $(MAKE) -s run T=$$t; done
	@$(PYTHON) tools/collect_results.py out > out/RESULTS.md
	@echo "  -> out/RESULTS.md"

wave:
	gtkwave -a $(OUT)/$(T).gtkw $(OUT)/$(T).vcd &

web:
	@$(PYTHON) tools/wave_web.py start

# 정적 사이트 (tools/wave_web.py export). SITE 는 별도 git 저장소(GitHub Pages)의 작업 디렉터리
SITE          ?= $(abspath $(SMART_RUN)/../../openc906-waves)
SITE_REPO     ?= https://github.com/hyukyeon/openc906/tree/study/smart_run/study

site:
	@$(PYTHON) tools/wave_web.py export $(SITE) --repo $(SITE_REPO)

web-stop:
	@$(PYTHON) tools/wave_web.py stop

clean:
	rm -rf out/*

distclean:
	rm -rf out/* build/*
