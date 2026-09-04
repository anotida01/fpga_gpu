# Snapshot override for sim:  make sim T=<test> SNAPSHOT=<snap>.
# If unset, resolved from tests.txt (test -> snapshot).
SNAPSHOT ?=
TESTS_MAP := tests.txt
SIM_OPTS ?= -linedebug
REG_RPRT_DIR := ./regression_reports
TIMESTAMP := $(shell date +%Y%m%d_%H%M%S)
REPORT_PREFIX := report_$(TIMESTAMP)
REPORT_LOG := $(REG_RPRT_DIR)/$(REPORT_PREFIX)/$(REPORT_PREFIX).log
REPORT_HTML := $(REG_RPRT_DIR)/$(REPORT_PREFIX)/$(REPORT_PREFIX).html
REPORT_ZIP := $(REG_RPRT_DIR)/$(REPORT_PREFIX).zip

# Build all snapshots (rows in snapshots.txt). Build one with SNAP=<snap_name>.
SNAP ?=

.PHONY: build sim regression reg r report_docs clean

build:
	./do_build_dut.sh $(SNAP)

# Syntax: make sim T=<test_name> [SNAPSHOT=<snap_name>]
# SNAPSHOT defaults to tests.txt lookup for T.
sim:
	@T="$(T)"; \
	test -n "$$T" || { echo "ERROR: make sim requires T=<test_name>"; exit 1; }; \
	if [ -z "$(SNAPSHOT)" ]; then \
		[ -f "$(TESTS_MAP)" ] || { echo "ERROR: $(TESTS_MAP) not found"; exit 1; }; \
		SNAP_RES=$$(awk -v t="$$T" 'NF>=2 && $$1==t {print $$2; exit}' "$(TESTS_MAP)"); \
		[ -n "$$SNAP_RES" ] || { echo "ERROR: test '$$T' not found in $(TESTS_MAP)"; exit 1; }; \
		echo "Resolved SNAPSHOT='$$SNAP_RES' for T='$$T' from $(TESTS_MAP)"; \
	else \
		SNAP_RES="$(SNAPSHOT)"; \
		echo "Using SNAPSHOT='$$SNAP_RES' (override from make arg)"; \
	fi; \
	./do_run_sim.sh "$$SNAP_RES" "$$T" $(SIM_OPTS)

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
