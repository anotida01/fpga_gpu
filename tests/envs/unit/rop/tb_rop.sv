`ifndef TB_ROP_SV
`define TB_ROP_SV

module tb_rop;
  import uvm_pkg::*;
  import pipe_pkg::*;
  import clk_rst_pkg::*;
  import rop_env_pkg::*;
  import rop_seq_pkg::*;
  `include "uvm_macros.svh"

  // Clock & Reset Interface
  clk_rst_if clk_rst_i();

  wire clk   = clk_rst_i.clk;
  wire rst_n = clk_rst_i.rst_n;
  wire reset = ~rst_n;

  // Interfaces
  pipe_if #(.DATA_W(256)) in_if(clk, rst_n);
  pipe_if #(.DATA_W(256)) out_if(clk, rst_n);

  // DUT signals
  logic signed [26:0] c0_i, c1_i, c2_i;
  logic signed [31:0] w0_i, w1_i, w2_i;
  logic [31:0]        x_i, y_i;
  logic [31:0]        x_o, y_o, c_o;
  logic               ready_i, valid_i;
  logic               ready_o, valid_o;

  // Unpack input side from in_if.data
  assign x_i  = in_if.data[31:0];
  assign y_i  = in_if.data[63:32];
  assign w0_i = in_if.data[95:64];
  assign w1_i = in_if.data[127:96];
  assign w2_i = in_if.data[159:128];
  assign c0_i = signed'(in_if.data[186:160]);
  assign c1_i = signed'(in_if.data[213:187]);
  assign c2_i = signed'(in_if.data[240:214]);

  assign valid_i = in_if.valid;
  assign in_if.ready = ready_o;

  // Pack output side into out_if.data
  assign out_if.data = {160'h0, c_o, y_o, x_o};
  assign out_if.valid = valid_o;
  assign ready_i = out_if.ready;

  // Instantiate DUT
  rop dut (
    .clk     (clk),
    .reset   (reset),
    .c0_i    (c0_i),
    .c1_i    (c1_i),
    .c2_i    (c2_i),
    .w0_i    (w0_i),
    .w1_i    (w1_i),
    .w2_i    (w2_i),
    .x_i     (x_i),
    .y_i     (y_i),
    .x_o     (x_o),
    .y_o     (y_o),
    .c_o     (c_o),
    .ready_i (ready_i),
    .valid_i (valid_i),
    .ready_o (ready_o),
    .valid_o (valid_o)
  );

  initial begin
    uvm_config_db#(virtual pipe_if #(.DATA_W(256)))::set(null, "*.in_agent*", "vif", in_if);
    uvm_config_db#(virtual pipe_if #(.DATA_W(256)))::set(null, "*.out_agent*", "vif", out_if);
    uvm_config_db#(virtual clk_rst_if)::set(null, "*", "vif", clk_rst_i);
    run_test();
  end

endmodule

`endif
