#!/usr/bin/bash

# exit on error
set -e

# compile test
xmvlog -messages -sv -linedebug -work work  ../../tests/testcases/test_program.sv

# elabortate overall design
xmelab -update -access +w+r+c -namemap_mixgen +DISABLEGENCHK -timescale 1ps/1ps work.tb

# start sim
xmsim -gui work.tb

# xrun -gui \
#      -top work.tb \
#      -xmvlogargs "-messages -sv -linedebug -work work" \
#      -xmelabargs "-access +w+r+c -namemap_mixgen +DISABLEGENCHK -timescale 1ps/1ps" \
#      ../../tests/testcases/test_program.sv \
