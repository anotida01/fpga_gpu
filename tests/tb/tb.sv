`timescale 1ps / 1ps

module tb ();

  // logic clk    = 1'b0;
  // logic reset  = 1'b1;
  logic [3:0] KEY;

  // localparam  CLOCK_PERIOD            = 20000; // Clock period in ps
  // localparam  INITIAL_RESET_CYCLES    = 10;  // Number of cycles to reset when simulation starts

  // avl_tb dut (
  //   .clk_clk(clk),
  //   .reset_reset_n(~reset),
  //   // .fpga_gpu_0_conduit_gpu_ready     (tp.gpu_ready),
  //   .fpga_gpu_0_conduit_gpu_valid     (tp.gpu_valid),
  //   .fpga_gpu_0_conduit_gpu_start     (tp.gpu_start),
  //   .fpga_gpu_0_conduit_dma_ready     (tp.dma_ready),
  //   .fpga_gpu_0_conduit_dma_valid     (tp.dma_valid),
  //   .fpga_gpu_0_conduit_dma_out       (tp.dma_out),   
  //   .fpga_gpu_0_conduit_gpu_address   (tp.gpu_address),
  //   .fpga_gpu_0_conduit_gpu_ctrl_done (tp.gpu_ctrl_done),
  //   .fpga_gpu_0_conduit_gpu_dma_ready (tp.gpu_dma_ready)
  // );

    wire [8:0] rop_backend_x;
    wire [7:0] rop_backend_y;
    wire [14:0] rop_backend_c;
    wire rop_backend_valid;

    gpu_sys dut (
    .gpu_0_rop_conduit_rop_backend_c     (rop_backend_c),
    .gpu_0_rop_conduit_rop_backend_valid (rop_backend_valid),
    .gpu_0_rop_conduit_rop_backend_x     (rop_backend_x),
    .gpu_0_rop_conduit_rop_backend_y     (rop_backend_y) 
  );

    // VGA 
    wire [9:0] VGA_R_10;
    wire [9:0] VGA_G_10;
    wire [9:0] VGA_B_10;
    wire VGA_BLANK, VGA_SYNC;
    assign VGA_R = VGA_R_10[9:2];
    assign VGA_G = VGA_G_10[9:2];
    assign VGA_B = VGA_B_10[9:2];

    wire [14:0] VGA_COLOUR = rop_backend_c;
    wire VGA_PLOT = rop_backend_valid;

    // top level I/O
    wire VGA_HS, VGA_VS, VGA_CLK;

    wire [8:0] VGA_X = rop_backend_x;
    wire [7:0] VGA_Y = rop_backend_y;

    wire clk = dut.clock_source_0_clk_clk;
    wire reset = KEY[0];
    vga_adapter vga1(
        .resetn(~reset), .clock(clk), .colour(VGA_COLOUR), .x(VGA_X), .y(VGA_Y),
        .plot(VGA_PLOT), .VGA_R(VGA_R_10), .VGA_G(VGA_G_10), .VGA_B(VGA_B_10), .*
    );
    defparam vga1.RESOLUTION = "320x240";
    defparam vga1.BITS_PER_COLOUR_CHANNEL = 5;

   
  test_program tp();

  // // Clock signal generator
  // always begin
  //   #(CLOCK_PERIOD / 2);
  //   clk = ~clk;
  // end

  // // Initial reset
  // initial begin
  //   repeat(INITIAL_RESET_CYCLES) @(posedge clk);
  //   reset = 1'b0;
  // end

endmodule 