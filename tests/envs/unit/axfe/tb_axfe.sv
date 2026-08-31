module tb_axfe;
  import uvm_pkg::*;
  import axi4lite_pkg::*;
  import pipe_pkg::*;
  import axfe_env_pkg::*;
  `include "uvm_macros.svh"

  logic clk;
  logic reset;

  // Clock generation
  initial begin
    clk = 0;
    forever #5ns clk = ~clk;
  end

  // Reset generation
  initial begin
    reset = 1;
    repeat(10) @(posedge clk);
    reset = 0;
  end

  wire rst_n = ~reset;

  // Interfaces
  axi4lite_if ctrl_if(clk, rst_n);
  axi4lite_if mstr_if(clk, rst_n);
  pipe_if     dma_req_if(clk, rst_n);
  pipe_if     dma_rsp_if(clk, rst_n);

  // DUT
  axil_gpu_front_end dut (
    .clk                   (clk),
    .reset                 (reset),
    
    // CTRL Slave
    .ctrl_axi_awaddr_i     (ctrl_if.awaddr),
    .ctrl_axi_awprot_i     (ctrl_if.awprot),
    .ctrl_axi_awvalid_i    (ctrl_if.awvalid),
    .ctrl_axi_awready_o    (ctrl_if.awready),
    .ctrl_axi_wdata_i      (ctrl_if.wdata),
    .ctrl_axi_wstrb_i      (ctrl_if.wstrb),
    .ctrl_axi_wvalid_i     (ctrl_if.wvalid),
    .ctrl_axi_wready_o     (ctrl_if.wready),
    .ctrl_axi_bresp_o      (ctrl_if.bresp),
    .ctrl_axi_bvalid_o     (ctrl_if.bvalid),
    .ctrl_axi_bready_i     (ctrl_if.bready),
    .ctrl_axi_araddr_i     (ctrl_if.araddr),
    .ctrl_axi_arprot_i     (ctrl_if.arprot),
    .ctrl_axi_arvalid_i    (ctrl_if.arvalid),
    .ctrl_axi_arready_o    (ctrl_if.arready),
    .ctrl_axi_rdata_o      (ctrl_if.rdata),
    .ctrl_axi_rresp_o      (ctrl_if.rresp),
    .ctrl_axi_rvalid_o     (ctrl_if.rvalid),
    .ctrl_axi_rready_i     (ctrl_if.rready),
    
    // MSTR Master
    .mstr_axi_awaddr_o     (mstr_if.awaddr),
    .mstr_axi_awprot_o     (mstr_if.awprot),
    .mstr_axi_awvalid_o    (mstr_if.awvalid),
    .mstr_axi_awready_i    (mstr_if.awready),
    .mstr_axi_wdata_o      (mstr_if.wdata),
    .mstr_axi_wstrb_o      (mstr_if.wstrb),
    .mstr_axi_wvalid_o     (mstr_if.wvalid),
    .mstr_axi_wready_i     (mstr_if.wready),
    .mstr_axi_bresp_i      (mstr_if.bresp),
    .mstr_axi_bvalid_i     (mstr_if.bvalid),
    .mstr_axi_bready_o     (mstr_if.bready),
    .mstr_axi_araddr_o     (mstr_if.araddr),
    .mstr_axi_arprot_o     (mstr_if.arprot),
    .mstr_axi_arvalid_o    (mstr_if.arvalid),
    .mstr_axi_arready_i    (mstr_if.arready),
    .mstr_axi_rdata_i      (mstr_if.rdata),
    .mstr_axi_rresp_i      (mstr_if.rresp),
    .mstr_axi_rvalid_i     (mstr_if.rvalid),
    .mstr_axi_rready_o     (mstr_if.rready),
    
    // GPU Handshake
    .gpu_dma_valid         (dma_req_if.valid),
    .gpu_dma_address       (dma_req_if.addr),
    .dma_ready             (dma_req_if.ready),
    .dma_valid             (dma_rsp_if.valid),
    .dma_out               (dma_rsp_if.data),
    .gpu_dma_ready         (dma_rsp_if.ready),
    
    // Ties / Unconnected
    .gpu_ctrl_done         (1'b0),
    .gpu_start             (),
    .output_mem_offset_addr_o (),
    .irq_gpu               ()
  );

  // UVM Config DB
  initial begin
    uvm_config_db#(virtual axi4lite_if)::set(null, "*.ctrl_agent*", "vif", ctrl_if);
    uvm_config_db#(virtual axi4lite_if)::set(null, "*.mstr_agent*", "vif", mstr_if);
    uvm_config_db#(virtual pipe_if)::set(null, "*.dma_req_agent*", "vif", dma_req_if);
    uvm_config_db#(virtual pipe_if)::set(null, "*.dma_rsp_agent*", "vif", dma_rsp_if);
    run_test();
  end

endmodule
