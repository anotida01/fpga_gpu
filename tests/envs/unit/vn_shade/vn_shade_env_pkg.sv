`ifndef VN_SHADE_ENV_PKG_SV
`define VN_SHADE_ENV_PKG_SV

package vn_shade_env_pkg;
  import uvm_pkg::*;
  import pipe_pkg::*;
  import clk_rst_pkg::*;
  `include "uvm_macros.svh"

  `include "vn_shade_scoreboard.sv"
  `include "env_vn_shade.sv"
endpackage

`endif
