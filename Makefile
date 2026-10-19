# Build the RAMB36E1 DOB_REG bug report.
#
#   make            build both targets with openXC7 into build/openxc7/
#   make vga_fail   build only the failing target with openXC7
#   make vga_ok     build only the working target with openXC7
#   make vivado     build both targets with Vivado into build/vivado/
#   make clean      remove build/
#
# The openXC7 toolchain is expected in $(OPENXC7) (default: /opt/openxc7).
# The flow is:
#
#   *.sv/*.v --[yosys]--> *.json --[nextpnr-xilinx]--> *.fasm --[fpga-as]--> *.bit

SHELL := /bin/bash

ROOT := $(patsubst %/,%,$(dir $(abspath $(lastword $(MAKEFILE_LIST)))))

OPENXC7     ?= /opt/openxc7
OPENXC7_ENV ?= $(OPENXC7)/export.sh
VIVADO      ?= vivado

PART   := xc7a35tcpg236-1
FAMILY := artix7
DBPART := $(shell echo $(PART) | sed -e 's/-[0-9]//g')

BUILD_DIR := $(ROOT)/build
CHIPDB    := $(BUILD_DIR)/chipdb
OSS_DIR   := $(BUILD_DIR)/openxc7

TARGETS   := vga_fail vga_ok
BITSTREAM := $(addprefix $(OSS_DIR)/,$(addsuffix .bit,$(TARGETS)))

SOURCES := $(ROOT)/clk_gen.v $(ROOT)/vga_memory.v
XDC     := $(ROOT)/basys3.xdc

.DELETE_ON_ERROR:

# Keep the intermediate netlists/FASM files for debugging.
.SECONDARY:

.PHONY: all
all: $(BITSTREAM)

.PHONY: vga_fail
vga_fail: $(OSS_DIR)/vga_fail.bit

.PHONY: vga_ok
vga_ok: $(OSS_DIR)/vga_ok.bit

.PHONY: vivado
vivado:
	$(VIVADO) -mode batch -source $(ROOT)/vivado.tcl

.PHONY: clean
clean:
	rm -rf $(BUILD_DIR)

$(BUILD_DIR) $(CHIPDB) $(OSS_DIR):
	mkdir -p $@

# --- Synthesis -------------------------------------------------------------
$(OSS_DIR)/%.yosys.json: $(SOURCES) $(ROOT)/%.sv $(XDC) | $(OSS_DIR)
	. $(OPENXC7_ENV) && \
	yosys -p "read_verilog -sv $(SOURCES) $(ROOT)/$*.sv; \
	          synth_xilinx -flatten -abc9 -arch xc7 -top $*; \
	          write_json $@"

# --- Chip database ---------------------------------------------------------
# xc7a35t and xc7a50t share the same die, so generate the xc7a50t database.
$(CHIPDB)/$(DBPART).bin: | $(CHIPDB)
	. $(OPENXC7_ENV) && \
	DIE=$$(echo $(PART) | sed -E 's/^(xc7z007s|xc7z012s|xc7z014s|xc7[azks][0-9]+t?|xc7vx[0-9]+t?).*/\1/'); \
	if [ "$$DIE" = xc7a35t ]; then DIE=xc7a50t; fi; \
	echo "generating chipdb for $$DIE ($(PART))"; \
	python3 $(OPENXC7)/share/nextpnr/himbaechel/uarch/xilinx/gen/xilinx_gen.py \
	    --xray $$PRJXRAY_DB_DIR/$(FAMILY) \
	    --device $$DIE \
	    --bba $(CHIPDB)/$(DBPART).bba && \
	bbasm -l $(CHIPDB)/$(DBPART).bba $@ && \
	rm -f $(CHIPDB)/$(DBPART).bba

# --- Place and route -------------------------------------------------------
$(OSS_DIR)/%.fasm: $(OSS_DIR)/%.yosys.json $(CHIPDB)/$(DBPART).bin $(XDC)
	. $(OPENXC7_ENV) && \
	nextpnr-xilinx --chipdb $(CHIPDB)/$(DBPART).bin \
	               --xdc $(XDC) \
	               --json $< \
	               --report $(OSS_DIR)/$*.nextpnr.rpt \
	               --threads 4 \
	               --write $(OSS_DIR)/$*.nextpnr.json \
	               --fasm $@

# --- Bitstream -------------------------------------------------------------
$(OSS_DIR)/%.bit: $(OSS_DIR)/%.fasm
	. $(OPENXC7_ENV) && \
	fpga-as --prjxray_db_path=$$PRJXRAY_DB_DIR/$(FAMILY) --part $(PART) $< > $@
