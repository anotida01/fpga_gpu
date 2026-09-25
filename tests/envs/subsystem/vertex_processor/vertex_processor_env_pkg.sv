`ifndef VERTEX_PROCESSOR_ENV_PKG_SV
`define VERTEX_PROCESSOR_ENV_PKG_SV

package vertex_processor_env_pkg;
  import uvm_pkg::*;
  import pipe_pkg::*;
  import clk_rst_pkg::*;
  `include "uvm_macros.svh"

  `include "vertex_processor_scoreboard.sv"
  `include "env_vertex_processor.sv"

endpackage

`endif
