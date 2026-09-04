interface pipe_if #(parameter int DATA_W = 32) (input logic clk, input logic rst_n);
  logic                 valid;
  logic                 ready;
  logic [31:0]          addr;
  logic [DATA_W-1:0]    data;

  clocking mon_cb @(posedge clk);
    default input #1ns;
    input valid, ready, addr, data;
  endclocking
endinterface
