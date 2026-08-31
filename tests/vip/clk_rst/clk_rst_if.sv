`ifndef CLK_RST_IF_SV
`define CLK_RST_IF_SV

interface clk_rst_if;
  logic clk;        // Generated DUT clock
  logic rst_n;      // Generated DUT active-low reset

  // Control knobs (managed by clk_rst_ctrl)
  real clk_period = 10000.0; // Clock period in ps (default: 10000 ps = 10 ns)
  bit  clk_en     = 1'b1;    // 1 = toggling, 0 = held low
  bit  reset_req  = 1'b0;    // Level: 1 = hold reset asserted (rst_n low)

  clocking cb @(posedge clk);
    default input #1ns;
    input clk, rst_n;
  endclocking
endinterface

`endif
