`ifndef TB_VN_SHADE_SV
`define TB_VN_SHADE_SV

module tb_vn_shade;
  import uvm_pkg::*;
  import pipe_pkg::*;
  import clk_rst_pkg::*;
  import vn_shade_env_pkg::*;
  import vn_shade_seq_pkg::*;
  `include "uvm_macros.svh"

  // Clock & Reset Interface
  clk_rst_if clk_rst_i();

  wire clk   = clk_rst_i.clk;
  wire rst_n = clk_rst_i.rst_n;
  wire reset = ~rst_n; // DUT reset is active high

  // Interfaces
  pipe_if #(.DATA_W(27)) in_if(clk, rst_n);
  pipe_if #(.DATA_W(27)) out_if(clk, rst_n);

  // Instantiate DUT
  vn_shade dut (
    .clk     (clk),
    .reset   (reset),
    .valid_i (in_if.valid),
    .ready_i (out_if.ready),
    .vn      (in_if.data[26:0]),
    .vn_o    (out_if.data),
    .valid_o (out_if.valid),
    .ready_o (in_if.ready)
  );

  initial begin
    uvm_config_db#(virtual pipe_if #(.DATA_W(27)))::set(null, "*.in_agent*", "vif", in_if);
    uvm_config_db#(virtual pipe_if #(.DATA_W(27)))::set(null, "*.out_agent*", "vif", out_if);
    uvm_config_db#(virtual clk_rst_if)::set(null, "*", "vif", clk_rst_i);
    run_test();
  end

endmodule

`endif
