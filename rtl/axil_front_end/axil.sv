

module axil_gpu_front_end (
  input  logic clk, reset,

  // DMA Master AXI Lite signals
  // todo: do we use SV interfaces? Qsys may not support this
  output logic              mstr_axi_awvalid_o,// AW
  input  logic              mstr_axi_awready_i,
  output logic [31:0]       mstr_axi_awaddr_o,
  output logic [ 2:0]       mstr_axi_awprot_o,
  output logic              mstr_axi_wvalid_o , // W
  input  logic              mstr_axi_wready_i,
  output logic [31:0]       mstr_axi_wdata_o,
  output logic [32/8-1:0]   mstr_axi_wstrb_o,
  input  logic              mstr_axi_bvalid_i, // B
  input  logic [1:0]        mstr_axi_bresp_i,
  output logic              mstr_axi_bready_o,
  output logic              mstr_axi_arvalid_o,// AR
  input  logic              mstr_axi_arready_i,
  output logic [31:0]       mstr_axi_araddr_o,
  output logic [ 2:0]       mstr_axi_arprot_o,
  input  logic              mstr_axi_rvalid_i, // R
  output logic              mstr_axi_rready_o,
  input  logic [31:0]       mstr_axi_rdata_i,
  input  logic [ 1:0]       mstr_axi_rresp_i,

  // CTRL slave AXI Lite signals
  input  logic              ctrl_axi_awvalid_i,// AW
  output logic              ctrl_axi_awready_o,
  input  logic [31:0]       ctrl_axi_awaddr_i,
  input  logic [ 2:0]       ctrl_axi_awprot_i,
  input  logic              ctrl_axi_wvalid_i , // W
  output logic              ctrl_axi_wready_o,
  input  logic [31:0]       ctrl_axi_wdata_i,
  input  logic [32/8-1:0]   ctrl_axi_wstrb_i,
  output logic              ctrl_axi_bvalid_o, // B
  output logic [1:0]        ctrl_axi_bresp_o,
  input  logic              ctrl_axi_bready_i,
  input  logic              ctrl_axi_arvalid_i,// AR
  output logic              ctrl_axi_arready_o,
  input  logic [31:0]       ctrl_axi_araddr_i,
  input  logic [ 2:0]       ctrl_axi_arprot_i,
  output logic              ctrl_axi_rvalid_o, // R
  input  logic              ctrl_axi_rready_i,
  output logic [31:0]       ctrl_axi_rdata_o,
  output logic [ 1:0]       ctrl_axi_rresp_o,

  // from gpu
  input  logic        gpu_dma_ready,
  input  logic        gpu_dma_valid,
  input  logic [31:0] gpu_dma_address,
  input  logic        gpu_ctrl_done,

  // to gpu
  output logic        gpu_start,
  output logic        dma_ready,
  output logic        dma_valid,
  output logic [31:0] dma_out,
  
  // top bus backend
  output logic [31:0] output_mem_offset_addr_o,

  // irq to cpu
  output logic        irq_gpu

);

  logic [31:0] input_mem_offset_addr;
  wire reset_n = ~reset;

  // WB Master Port
  logic [31:0]     mstr_wb_addr;
  logic            mstr_wb_cyc;
  logic            mstr_wb_stb;
  logic            mstr_wb_we;
  logic [31:0]     mstr_wb_data_i;
  logic [31:0]     mstr_wb_data_o;
  logic [32/8-1:0] mstr_wb_sel;
  logic            mstr_wb_ack;
  logic            mstr_wb_err;
  logic            mstr_wb_stall;

  // WB Slave Port
  logic [31:0]     ctrl_wb_addr;
  logic            ctrl_wb_cyc;
  logic            ctrl_wb_stb;
  logic            ctrl_wb_we;
  logic [31:0]     ctrl_wb_data_i;
  logic [31:0]     ctrl_wb_data_o;
  logic [32/8-1:0] ctrl_wb_sel;
  logic            ctrl_wb_ack;
  logic            ctrl_wb_err;
  logic            ctrl_wb_stall;

  axil_ctrl_slave avlmm_ctrl_slave0 (
    .clk,
    .reset,
    .i_wb_cyc                 (ctrl_wb_cyc),
    .i_wb_stb                 (ctrl_wb_stb),
    .i_wb_we                  (ctrl_wb_we),
    .i_wb_addr                (ctrl_wb_addr),
    .i_wb_data                (ctrl_wb_data_i),
    .i_wb_sel                 (ctrl_wb_sel),
    .o_wb_data                (ctrl_wb_data_o),
    .o_wb_ack                 (ctrl_wb_ack),
    .o_wb_stall               (ctrl_wb_stall),
    .o_wb_err                 (ctrl_wb_err),
    .start_o                  (gpu_start),
    .ready_i                  (gpu_ctrl_done),
    .input_mem_offset_addr_o  (input_mem_offset_addr),
    .output_mem_offset_addr_o (output_mem_offset_addr_o),
    .irq_gpu                  (irq_gpu)
  );

  axlite2wbsp ctrl_axil2wbsp_inst (
    .i_clk          (clk),
    .i_axi_reset_n  (reset_n),
    .i_axi_awaddr   (ctrl_axi_awaddr_i),
    .i_axi_awprot   (ctrl_axi_awprot_i),
    .i_axi_awvalid  (ctrl_axi_awvalid_i),
    .o_axi_awready  (ctrl_axi_awready_o),
    .i_axi_wdata    (ctrl_axi_wdata_i),
    .i_axi_wstrb    (ctrl_axi_wstrb_i),
    .i_axi_wvalid   (ctrl_axi_wvalid_i),
    .o_axi_wready   (ctrl_axi_wready_o),
    .o_axi_bresp    (ctrl_axi_bresp_o),
    .o_axi_bvalid   (ctrl_axi_bvalid_o),
    .i_axi_bready   (ctrl_axi_bready_i),
    .i_axi_araddr   (ctrl_axi_araddr_i),
    .i_axi_arprot   (ctrl_axi_arprot_i),
    .i_axi_arvalid  (ctrl_axi_arvalid_i),
    .o_axi_arready  (ctrl_axi_arready_o),
    .o_axi_rdata    (ctrl_axi_rdata_o),
    .o_axi_rresp    (ctrl_axi_rresp_o),
    .o_axi_rvalid   (ctrl_axi_rvalid_o),
    .i_axi_rready   (ctrl_axi_rready_i),

    // .o_reset        (), // todo: warning! this is disconnected and might be important!
    .o_wb_cyc       (ctrl_wb_cyc),
    .o_wb_stb       (ctrl_wb_stb),
    .o_wb_we        (ctrl_wb_we),
    .o_wb_addr      (ctrl_wb_addr),
    .o_wb_data      (ctrl_wb_data_i),
    .o_wb_sel       (ctrl_wb_sel),
    .i_wb_data      (ctrl_wb_data_o),
    .i_wb_ack       (ctrl_wb_ack),
    .i_wb_stall     (ctrl_wb_stall),
    .i_wb_err       (ctrl_wb_err)
  );

  axil_dma_master axil_dma_master0 (
    .clk,
    .reset,

    // WB Master Port
    .wb_addr_o          (mstr_wb_addr),
    .wb_cyc_o           (mstr_wb_cyc),
    .wb_stb_o           (mstr_wb_stb),
    .wb_we_o            (mstr_wb_we),
    .wb_data_o          (mstr_wb_data_o),
    .wb_data_i          (mstr_wb_data_i),
    .wb_sel_o           (mstr_wb_sel),
    .wb_ack_i           (mstr_wb_ack),
    .wb_err_i           (mstr_wb_err),
    .wb_stall_i         (mstr_wb_stall),

    // to gpu
    .valid_o            (dma_valid),
    .ready_o            (dma_ready),
    .dma_out            (dma_out),

    // from gpu
    .ready_i            (gpu_dma_ready),
    .valid_i            (gpu_dma_valid),
    .address_i          (gpu_dma_address),
    
    // from GPU CTRL REGs
    .input_mem_offset_addr_i  (input_mem_offset_addr)
  );

  // todo: this should connect to the internal bus now
  wbm2axilite #(
    .C_AXI_ADDR_WIDTH(32)
  ) mstr_wbm2axil_inst (
    .i_clk          (clk),
    .i_reset        (reset),
    .i_wb_addr      (mstr_wb_addr),
    .i_wb_cyc       (mstr_wb_cyc),
    .i_wb_stb       (mstr_wb_stb),
    .i_wb_we        (mstr_wb_we),
    .i_wb_data      (mstr_wb_data_o),
    .i_wb_sel       (mstr_wb_sel),
    .o_wb_data      (mstr_wb_data_i),
    .o_wb_ack       (mstr_wb_ack),
    .o_wb_err       (mstr_wb_err),
    .o_wb_stall     (mstr_wb_stall),

    .o_axi_awvalid  (mstr_axi_awvalid_o), 
    .i_axi_awready  (mstr_axi_awready_i),
    .o_axi_awaddr   (mstr_axi_awaddr_o),
    .o_axi_awprot   (mstr_axi_awprot_o),

    .o_axi_wvalid   (mstr_axi_wvalid_o),
    .i_axi_wready   (mstr_axi_wready_i),
    .o_axi_wdata    (mstr_axi_wdata_o),
    .o_axi_wstrb    (mstr_axi_wstrb_o),

    .i_axi_bvalid   (mstr_axi_bvalid_i),
    .i_axi_bresp    (mstr_axi_bresp_i),
    .o_axi_bready   (mstr_axi_bready_o),

    .o_axi_arvalid  (mstr_axi_arvalid_o),
    .i_axi_arready  (mstr_axi_arready_i),
    .o_axi_araddr   (mstr_axi_araddr_o),
    .o_axi_arprot   (mstr_axi_arprot_o),

    .i_axi_rvalid   (mstr_axi_rvalid_i),
    .o_axi_rready   (mstr_axi_rready_o),
    .i_axi_rdata    (mstr_axi_rdata_i),
    .i_axi_rresp    (mstr_axi_rresp_i)
  );

endmodule

