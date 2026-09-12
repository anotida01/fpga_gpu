`ifndef ROP_BACKEND_ENV_PKG_SV
`define ROP_BACKEND_ENV_PKG_SV

package rop_backend_env_pkg;
  import uvm_pkg::*;
  import pipe_pkg::*;
  import axi4lite_pkg::*;
  import clk_rst_pkg::*;
  `include "uvm_macros.svh"

  `include "rop_backend_scoreboard.sv"
  `include "env_rop_backend.sv"
endpackage

`endif
