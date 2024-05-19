


module avlmm_gpu_front_end (
  input  logic clk, reset,

  // DMA Avalon MM Master port
  input  logic [31:0] master_readdata,
  input  logic [ 0:0] master_waitrequest,
  output logic [31:0] master_address, // must be aligned to readdata
  output logic [ 0:0] master_read,
  output logic [ 3:0] master_byteenable,

  // CTRL Avalon MM Slave port
  input  logic [ 3:0] slave_address,
  input  logic [31:0] slave_writedata,
  input  logic [ 0:0] slave_write,
  input  logic [ 0:0] slave_read,
  input  logic [ 3:0] slave_byteenable,
  output logic [31:0] slave_readdata,
  output logic [ 0:0] slave_waitrequest,

  // from gpu
  input  logic [ 0:0] gpu_dma_ready,
  input  logic [ 0:0] gpu_dma_valid,
  input  logic [31:0] gpu_dma_address,
  input  logic [ 0:0] gpu_ctrl_done,

  // to gpu
  output logic [ 0:0] gpu_start,
  output logic [ 0:0] dma_ready,
  output logic [ 0:0] dma_valid,
  output logic [31:0] dma_out
);

  logic [31:0] mem_offset_addr;

  avlmm_ctrl_slave avlmm_ctrl_slave0 (
    .clk,
    .reset,
    .address            (slave_address),
    .writedata          (slave_writedata),
    .write              (slave_write),
    .read               (slave_read),
    .byteenable         (slave_byteenable),
    .readdata           (slave_readdata),
    .waitrequest        (slave_waitrequest),
    .start_o            (gpu_start),
    .ready_i            (gpu_ctrl_done),
    .mem_offset_addr_o  (mem_offset_addr)
  );

  avlmm_dma_master avlmm_dma_master0 (
    .clk,
    .reset,
    .readdata           (master_readdata),
    .waitrequest        (master_waitrequest),
    .address            (master_address),
    .read               (master_read),
    .byteenable         (master_byteenable),
    .valid_o            (dma_valid),
    .ready_o            (dma_ready),
    .dma_out            (dma_out),
    .ready_i            (gpu_dma_ready),
    .valid_i            (gpu_dma_valid),
    .address_i          (gpu_dma_address),
    .mem_offset_addr_i  (mem_offset_addr)
  );

endmodule

