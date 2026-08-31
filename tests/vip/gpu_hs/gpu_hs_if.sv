`ifndef GPU_HS_IF_SV
`define GPU_HS_IF_SV

interface gpu_hs_if (input logic clk, input logic rst_n);
  logic        start;
  logic        done;
  logic [31:0] out_mem_off;
  logic        irq;

  clocking mon_cb @(posedge clk);
    default input #1ns;
    input start, done, out_mem_off, irq;
  endclocking
endinterface

`endif
