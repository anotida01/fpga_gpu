#!/usr/bin/bash

# TODO: if we have multiple tests, we may need to parameterize

# exit on error
set -e

# compile IP & Intel libraries
# source ../../ip/madd/madd_sim/cadence/xcelium_setup.sh
source ../../qsys/gpu_sys/simulation/cadence/xmsim_setup.sh

# compile local HDL files & some IPs
xmvlog -messages -sv -f vertex_processor.f -work work 

# elabortate overall design
xmelab -update -access +w+r+c -namemap_mixgen +DISABLEGENCHK -timescale 1ps/1ps work.tb