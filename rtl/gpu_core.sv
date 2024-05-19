

module gpu_core (
  input logic  [ 0:0] clk, reset,

  // front end
  input  logic [ 0:0] start_i,
  input  logic [31:0] dma_data_i,
  input  logic [ 0:0] dma_ready_i,
  input  logic [ 0:0] dma_valid_i,
  output logic [31:0] gpu_address_o,
  output logic [ 0:0] gpu_valid_o,
  output logic [ 0:0] gpu_done_o,
  output logic [ 0:0] gpu_ready_o,

  // back end
  input  logic [ 0:0] rop_backend_ready,
  output logic [31:0] gpu_rop_x,
  output logic [31:0] gpu_rop_y,
  output logic [31:0] gpu_rop_c,
  output logic [ 0:0] gpu_rop_valid
  
);
  // logic [31:0] q;
  // logic [13:0] address;
  // logic gpu_valid_o, gpu_done_o;
  // logic [26:0] v_data;

  // logic , start;
  // logic clk;

  logic [107:0] vertex_xyzw;
  logic v_fifo_wrreq, v_fifo_rdreq;
  logic v_fifo_full, v_fifo_empty;
  logic fifo_rdreq;
  logic [26:0] shade_vn_o;
  logic vn_fifo_full, vn_fifo_wrreq;

  vertex_processor vertex_processor0 (
    .clk,
    .reset,
    .start_i,
    .dma_data_i,
    .dma_ready_i,
    .dma_valid_i,
    .gpu_valid_o,
    .gpu_address_o,
    .gpu_done_o,
    .gpu_ready_o,
    .vertex_xyzw,
    .v_fifo_wrreq,
    .v_fifo_full,
    .shade_vn_o,
    .vn_fifo_wrreq,
    .vn_fifo_full
  );

  wire [107:0] v_fifo_q;
  fifo_108x32 v_fifo (
    .clock(clk),
    .data(vertex_xyzw),
    .rdreq(v_fifo_rdreq),
    .sclr(reset),
    .wrreq(v_fifo_wrreq),
    .empty(v_fifo_empty),
    .full(v_fifo_full),
    .q(v_fifo_q)
  );

  wire [26:0] vn_fifo_q;
  wire vn_fifo_rdreq;
  wire vn_fifo_empty;
  fifo_27x32 vn_fifo(
    .clock(clk),
    .data(shade_vn_o),
    .rdreq(vn_fifo_rdreq),
    .sclr(reset),
    .wrreq(vn_fifo_wrreq),
    .empty(vn_fifo_empty),
    .full(vn_fifo_full),
    .q(vn_fifo_q)
  );

  wire [31:0] raster_w0, raster_w1, raster_w2;
  wire [31:0] raster_c0, raster_c1, raster_c2;
  wire [31:0] raster_x, raster_y;
  wire raster_valid, rop_ready;
  raster raster0 (
    .v_fifo_q,
    .v_fifo_empty,
    .v_fifo_rdreq,
    .vn_fifo_q,
    .vn_fifo_empty,
    .vn_fifo_rdreq,
    .w0_o(raster_w0),
    .w1_o(raster_w1),
    .w2_o(raster_w2),
    .c0_o(raster_c0),
    .c1_o(raster_c1),
    .c2_o(raster_c2),
    .x_o(raster_x),
    .y_o(raster_y),
    .valid_o(raster_valid),
    .ready_i(rop_ready),
    .*
  );

  rop rop0 (
    .c0_i(raster_c0),
    .c1_i(raster_c1),
    .c2_i(raster_c2),
    .w0_i(raster_w0),
    .w1_i(raster_w1),
    .w2_i(raster_w2),
    .x_i(raster_x),
    .y_i(raster_y),
    .x_o(gpu_rop_x),
    .y_o(gpu_rop_y),
    .c_o(gpu_rop_c),
    .ready_i(rop_backend_ready),
    .valid_i(raster_valid),
    .ready_o(rop_ready),
    .valid_o(gpu_rop_valid),
    .*
  );

endmodule

