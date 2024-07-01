
# script defines aliases to compile design files within gpu_sys
source ../../qsys/gpu_sys/simulation/mentor/msim_setup.tcl

# call compilation aliases
dev_com
com

# compile test bench components not included in design files!
eval vlog -work ./libraries/work/ ../../rtl/vga-core/vga_adapter.sv
eval vlog -work ./libraries/work/ ../../rtl/vga-core/vga_address_translator.sv
eval vlog -work ./libraries/work/ ../../rtl/vga-core/vga_controller.sv
eval vlog -work ./libraries/work/ ../../rtl/vga-core/vga_pll.sv

# compile testbench
eval vlog -work ./libraries/work/ ../../tests/tb/tb.sv
