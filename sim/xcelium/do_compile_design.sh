#!/usr/bin/bash

# exit on error
set -e

# compile design files within gpu_sys
source ../../qsys/gpu_axil_sys/simulation/xcelium/xcelium_setup.sh

# compile local HDL files
xmvlog -messages -sv -f vertex_processor.f -linedebug -work work 

# # elabortate overall design
# xmelab -update -access +w+r+c -namemap_mixgen +DISABLEGENCHK -timescale 1ps/1ps work.tb