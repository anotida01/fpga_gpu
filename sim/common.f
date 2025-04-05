# NOTE: paths are relative to /sim/simulator/.

# TODO: It's undecided whether these files should be unique per TC or TB or just common to all???
# All shall be revealed soon

# Project RTL Files
../../rtl/axil_front_end/axil_control.sv
../../rtl/axil_front_end/axil_dma.sv
../../rtl/axil_front_end/axil.sv
../../rtl/axil_interconnect_wrap.v
../../rtl/axil_sys_top.sv

# Submodule RTL files
# wb2axi
../../submodules/wb2axip/rtl/wbm2axilite.v
../../submodules/wb2axip/rtl/axilrd2wbsp.v
../../submodules/wb2axip/rtl/axilwr2wbsp.v
../../submodules/wb2axip/rtl/wbarbiter.v
../../submodules/wb2axip/rtl/axlite2wbsp.v

# verilog-axi
../../submodules/verilog-axi/rtl/arbiter.v
../../submodules/verilog-axi/rtl/priority_encoder.v
../../submodules/verilog-axi/rtl/axil_register.v
../../submodules/verilog-axi/rtl/axil_register_rd.v
../../submodules/verilog-axi/rtl/axil_register_wr.v
../../submodules/verilog-axi/rtl/axil_crossbar.v
../../submodules/verilog-axi/rtl/axil_crossbar_rd.v
../../submodules/verilog-axi/rtl/axil_crossbar_wr.v
../../submodules/verilog-axi/rtl/axil_crossbar_addr.v
../../submodules/verilog-axi/rtl/axil_ram.v