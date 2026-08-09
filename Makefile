SHELL := /bin/bash
.SHELLFLAGS := -eu -o pipefail -c
.DEFAULT_GOAL := help
.DELETE_ON_ERROR:

ROOT := $(abspath $(dir $(firstword $(MAKEFILE_LIST))))
COMMON_ROOT ?= $(abspath $(ROOT)/../common)
BUILD_DIR ?= $(ROOT)/build
IVERILOG ?= iverilog
VVP ?= vvp
VERILATOR ?= verilator
VERIBLE_FORMAT ?= verible-verilog-format
CLANG_FORMAT ?= clang-format-14
HOST_CC ?= cc
PYTHON ?= python3
SBY ?= sby
SV2V ?= sv2v

RTL_SRCS := rtl/ps2_filter.sv rtl/ps2_rx.sv rtl/ps2_tx.sv rtl/ps2_core.sv \
	rtl/ps2_reg.sv rtl/ps2_if.sv rtl/apb4_ps2.sv
RTL_HDRS := rtl/ps2_define.svh
DV_SRCS := dv/model/ps2_device_model.sv dv/unit/ps2_tb.sv
C_SRCS := sw/src/ps2.c sw/src/ps2_keyboard.c sw/src/ps2_mouse.c sw/tests/test_ps2.c
C_HDRS := sw/include/ps2.h sw/include/ps2_keyboard.h sw/include/ps2_mouse.h \
	sw/include/ps2_regs.h

COMMON_APB := $(COMMON_ROOT)/rtl/interface/apb4_if.sv
COMMON_REGISTER := $(COMMON_ROOT)/rtl/utils/register.sv
COMMON_FIFO := $(COMMON_ROOT)/rtl/utils/fifo.sv
COMMON_CDC := $(COMMON_ROOT)/rtl/cdc/cdc_sync.sv
COMMON_XCHECKER := $(COMMON_ROOT)/rtl/utils/xchecker.sv
IVERILOG_OUT := $(BUILD_DIR)/iverilog/ps2_tb.vvp
VERILATOR_DIR := $(BUILD_DIR)/verilator
HOST_TEST := $(BUILD_DIR)/host/test_ps2

.PHONY: help doctor format format-check register-check lint test test-iverilog \
	test-verilator test-host synth formal clean

help:
	@printf '%s\n' \
	  'ps2 targets:' \
	  '  doctor          verify required tools and Common checkout' \
	  '  format-check    verify SystemVerilog and C formatting' \
	  '  register-check  compare hand-written RTL and C definitions' \
	  '  lint            run Verilator lint on the APB4 wrapper' \
	  '  test            run Icarus, Verilator, and host C tests' \
	  '  synth           synthesize the PS/2 controller with Yosys' \
	  '  formal          prove controller properties with SBY/Bitwuzla'

doctor:
	@for tool in $(IVERILOG) $(VVP) $(VERILATOR) $(VERIBLE_FORMAT) $(CLANG_FORMAT) \
		$(HOST_CC) $(PYTHON) yosys $(SBY) $(SV2V) bitwuzla; do \
		command -v $$tool >/dev/null || { echo "missing tool: $$tool" >&2; exit 1; }; \
	done
	@test -f $(COMMON_APB) || { echo "missing Common checkout: $(COMMON_ROOT)" >&2; exit 1; }

format:
	$(VERIBLE_FORMAT) --flagfile=$(ROOT)/.verible-format --inplace $(RTL_SRCS) $(RTL_HDRS) \
		$(DV_SRCS) formal/ps2_formal.sv
	$(CLANG_FORMAT) -i $(C_SRCS) $(C_HDRS)

format-check:
	@set -e; for file in $(RTL_SRCS) $(RTL_HDRS) $(DV_SRCS) formal/ps2_formal.sv; do \
		tmp=$$(mktemp); $(VERIBLE_FORMAT) --flagfile=$(ROOT)/.verible-format $$file > $$tmp; \
		cmp -s $$file $$tmp || { echo "SystemVerilog format mismatch: $$file" >&2; \
		rm -f $$tmp; exit 1; }; rm -f $$tmp; \
	done
	@set -e; for file in $(C_SRCS) $(C_HDRS); do \
		tmp=$$(mktemp); $(CLANG_FORMAT) $$file > $$tmp; cmp -s $$file $$tmp || { \
			echo "C format mismatch: $$file" >&2; rm -f $$tmp; exit 1; }; rm -f $$tmp; \
	done

register-check:
	$(PYTHON) scripts/check_register_parity.py

lint:
	$(VERILATOR) --lint-only --timing -Wall -Wno-fatal -Wno-DECLFILENAME -Wno-GENUNNAMED \
		-Wno-UNDRIVEN -Wno-UNUSEDSIGNAL \
		--top-module apb4_ps2 -DSV_ASSRT_DISABLE -Irtl -I$(COMMON_ROOT)/rtl/interface \
		-I$(COMMON_ROOT)/rtl -I$(COMMON_ROOT)/rtl/utils $(COMMON_APB) $(COMMON_REGISTER) \
		$(COMMON_FIFO) $(COMMON_CDC) $(COMMON_XCHECKER) $(RTL_SRCS)

$(IVERILOG_OUT): $(RTL_SRCS) $(RTL_HDRS) $(DV_SRCS)
	@mkdir -p $(@D)
	$(IVERILOG) -g2012 -DSV_ASSRT_DISABLE -Irtl -I$(COMMON_ROOT)/rtl -o $@ \
		$(COMMON_REGISTER) $(COMMON_FIFO) $(COMMON_CDC) rtl/ps2_filter.sv rtl/ps2_rx.sv \
		rtl/ps2_tx.sv rtl/ps2_core.sv rtl/ps2_reg.sv $(DV_SRCS)

test-iverilog: $(IVERILOG_OUT)
	$(VVP) $(IVERILOG_OUT) | tee $(BUILD_DIR)/iverilog/test.log
	@grep -q PS2_TEST_PASS $(BUILD_DIR)/iverilog/test.log

test-verilator:
	@mkdir -p $(VERILATOR_DIR) $(BUILD_DIR)/ccache-tmp $(BUILD_DIR)/tmp
	CCACHE_DISABLE=1 CCACHE_TEMPDIR=$(BUILD_DIR)/ccache-tmp TMPDIR=$(BUILD_DIR)/tmp \
	$(VERILATOR) --binary --timing -Wall -Wno-fatal -Wno-DECLFILENAME -Wno-GENUNNAMED \
	-Wno-TIMESCALEMOD -Wno-UNUSEDSIGNAL -DSV_ASSRT_DISABLE \
	--Mdir $(VERILATOR_DIR) --top-module ps2_tb -Irtl -I$(COMMON_ROOT)/rtl \
	$(COMMON_REGISTER) $(COMMON_FIFO) $(COMMON_CDC) rtl/ps2_filter.sv rtl/ps2_rx.sv \
	rtl/ps2_tx.sv rtl/ps2_core.sv rtl/ps2_reg.sv $(DV_SRCS)
	$(VERILATOR_DIR)/Vps2_tb | tee $(VERILATOR_DIR)/test.log
	@grep -q PS2_TEST_PASS $(VERILATOR_DIR)/test.log

$(HOST_TEST): $(C_SRCS) $(C_HDRS)
	@mkdir -p $(@D)
	$(HOST_CC) -std=c11 -Wall -Wextra -Werror -pedantic -Isw/include $(C_SRCS) -o $@

test-host: $(HOST_TEST)
	$(HOST_TEST)

test: test-iverilog test-verilator test-host

synth:
	@mkdir -p $(BUILD_DIR)/synth
	$(SV2V) --top ps2_reg -DSV_ASSRT_DISABLE -Irtl -I$(COMMON_ROOT)/rtl $(COMMON_REGISTER) $(COMMON_FIFO) \
		$(COMMON_CDC) rtl/ps2_filter.sv rtl/ps2_rx.sv rtl/ps2_tx.sv rtl/ps2_core.sv \
		rtl/ps2_reg.sv --write=$(BUILD_DIR)/synth/ps2_reg.v
	yosys -p 'read_verilog $(BUILD_DIR)/synth/ps2_reg.v; hierarchy -top ps2_reg; proc; opt; check; stat' \
		| tee $(BUILD_DIR)/synth/yosys.log

formal:
	@mkdir -p $(BUILD_DIR)/formal-src
	$(SV2V) --top ps2_formal -DFORMAL -DSV_ASSRT_DISABLE -Irtl -I$(COMMON_ROOT)/rtl \
		$(COMMON_REGISTER) $(COMMON_FIFO) $(COMMON_CDC) rtl/ps2_filter.sv rtl/ps2_rx.sv \
		rtl/ps2_tx.sv rtl/ps2_core.sv rtl/ps2_reg.sv formal/ps2_formal.sv \
		--write=$(BUILD_DIR)/formal-src/ps2_formal.v
	$(SBY) -f -d $(BUILD_DIR)/formal formal/ps2.sby

clean:
	rm -rf $(BUILD_DIR)