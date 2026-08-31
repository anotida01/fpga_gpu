interface pipe_if (input logic clk, input logic rst_n);
  logic        valid;
  logic        ready;
  logic [31:0] addr;
  logic [31:0] data;

  clocking mon_cb @(posedge clk);
    default input #1ns;
    input valid, ready, addr, data;
  endclocking
endinterface
