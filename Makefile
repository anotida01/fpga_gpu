
VENV_PATH ?= debian_host_venv
PYTHON := $(VENV_PATH)/bin/python
PEAKRDL := $(VENV_PATH)/bin/peakrdl
SYSRDL_SRC ?= fpga_gpu_ctrl_regmap.rdl
SYSRDL_SRC_NAME := $(basename $(SYSRDL_SRC))
SYSRDL_SRC_PATH := docs/$(SYSRDL_SRC)
SYSRDL_C ?= gpu_regs.h
SYSRDL_C_PATH := sw/driver/$(SYSRDL_C)

BUS_MASTERS := 2
BUS_SLAVES := 3

# the generated path should be based off SYSRDL_SRC so that we can host multiple rdl files at the same time!
build_docs:
	$(PEAKRDL) html $(SYSRDL_SRC_PATH) -o docs/generated/$(SYSRDL_SRC_NAME)/html
	$(PEAKRDL) c-header -b ltoh --std gnu99 $(SYSRDL_SRC_PATH) -o $(SYSRDL_C_PATH)
	sed -i 's/#include <stdint.h>/#include <linux\/types.h>/g' $(SYSRDL_C_PATH) 

docs : build_docs

docs_webserver: build_docs
	$(PYTHON) -m http.server 8000 --directory docs/generated/ --bind 0.0.0.0

interconnect:
	$(PYTHON) submodules/verilog-axi/rtl/axil_crossbar_wrap.py -p $(BUS_SLAVES) $(BUS_MASTERS) -o rtl/axil_interconnect_wrap.v

copy_drv_host_to_remote:
	rsync -avz /home/ano/proj/fpga_gpu/sw/driver/ root@de1soc.local:/home/ano/proj/fpga_gpu/sw/driver/

copy_drv_remote_to_host:
	rsync -avz root@de1soc.local:/home/ano/proj/fpga_gpu/sw/driver/ /home/ano/proj/fpga_gpu/sw/driver/
