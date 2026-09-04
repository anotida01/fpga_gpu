`ifndef ROP_ENV_PKG_SV
`define ROP_ENV_PKG_SV

package rop_env_pkg;
  import uvm_pkg::*;
  import pipe_pkg::*;
  import clk_rst_pkg::*;
  `include "uvm_macros.svh"

  `include "rop_scoreboard.sv"
  `include "env_rop.sv"
endpackage

`endif
