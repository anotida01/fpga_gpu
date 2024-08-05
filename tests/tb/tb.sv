`timescale 1ps / 1ps

module tb ();

  logic [3:0] KEY;

  // localparam  CLOCK_PERIOD            = 20000; // Clock period in ps
  // localparam  INITIAL_RESET_CYCLES    = 10;  // Number of cycles to reset when simulation starts

    wire [8:0] rop_backend_x;
    wire [7:0] rop_backend_y;
    wire [14:0] rop_backend_c;
    wire rop_backend_valid;

    logic gpu_0_vga_conduit_vga_b       ;
    logic gpu_0_vga_conduit_vga_blank_n ;
    logic gpu_0_vga_conduit_vga_clk     ;
    logic gpu_0_vga_conduit_vga_g       ;
    logic gpu_0_vga_conduit_vga_hs      ;
    logic gpu_0_vga_conduit_vga_r       ;
    logic gpu_0_vga_conduit_vga_sync_n  ;
    logic gpu_0_vga_conduit_vga_vs      ;
    
    gpu_sys dut (
    .gpu_0_vga_conduit_vga_b       ,       // gpu_0_vga_conduit.vga_b
    .gpu_0_vga_conduit_vga_blank_n , //                  .vga_blank_n
    .gpu_0_vga_conduit_vga_clk     ,     //                  .vga_clk
    .gpu_0_vga_conduit_vga_g       ,       //                  .vga_g
    .gpu_0_vga_conduit_vga_hs      ,      //                  .vga_hs
    .gpu_0_vga_conduit_vga_r       ,       //                  .vga_r
    .gpu_0_vga_conduit_vga_sync_n  ,  //                  .vga_sync_n
    .gpu_0_vga_conduit_vga_vs             //                  .vga_vs
  );

  test_program tp();


endmodule 