
# compile test
eval vlog -work ./libraries/work/ -sv ../../tests/testcases/test_program.sv -L altera_common_sv_packages

# set this to test name
set TOP_LEVEL_NAME "tb"

elab_debug

# bringup vga gui
source de1_vga_gui.tcl
