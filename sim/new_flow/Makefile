SNAPSHOT ?= gpu_dut_snap
SIM_OPTS ?= -linedebug
REG_RPRT_DIR := ./regression_reports
TIMESTAMP := $(shell date +%Y%m%d_%H%M%S)
REPORT_PREFIX := report_$(TIMESTAMP)
REPORT_LOG := $(REG_RPRT_DIR)/$(REPORT_PREFIX)/$(REPORT_PREFIX).log
REPORT_HTML := $(REG_RPRT_DIR)/$(REPORT_PREFIX)/$(REPORT_PREFIX).html
REPORT_ZIP := $(REG_RPRT_DIR)/$(REPORT_PREFIX).zip

.PHONY: build sim regression reg r report_docs clean

build:
	./do_build_dut.sh $(SNAPSHOT)

# Syntax: make sim T=<test_name> [SNAPSHOT=<snap_name>]
sim:
	./do_run_sim.sh $(SNAPSHOT) $(T) $(SIM_OPTS)

s: sim

regression: $(REPORT_ZIP)
reg: regression
r: regression

$(REPORT_ZIP): report_docs
	cd $(REG_RPRT_DIR) && zip -r $(REPORT_PREFIX).zip $(REPORT_PREFIX)

report_docs:
	mkdir -p $(REG_RPRT_DIR)/$(REPORT_PREFIX)
	-pytest -v -rP -n auto --report-log=$(REPORT_LOG) --html=$(REPORT_HTML) regression.py

clean:
	rm -rf regression_logs/
	rm -rf $(REG_RPRT_DIR)
	rm -rf runs/
	rm -rf xcelium.d/
	rm -f xrun.log xrun.history
