module axil_sys_top #(
  parameter ADDR_WIDTH = 32,
  parameter DATA_WIDTH = 32,
  parameter STRB_WIDTH = (DATA_WIDTH/8)
)(
  input clk, reset,

  // one of the AXIL slave interfaces is exported out for use by the CPU
  input   logic [ADDR_WIDTH-1:0]  s00_axil_awaddr,
  input   logic [2:0]             s00_axil_awprot,
  input   logic                   s00_axil_awvalid,
  output  logic                   s00_axil_awready,
  input   logic [DATA_WIDTH-1:0]  s00_axil_wdata,
  input   logic [STRB_WIDTH-1:0]  s00_axil_wstrb,
  input   logic                   s00_axil_wvalid,
  output  logic                   s00_axil_wready,
  output  logic [1:0]             s00_axil_bresp,
  output  logic                   s00_axil_bvalid,
  input   logic                   s00_axil_bready,
  input   logic [ADDR_WIDTH-1:0]  s00_axil_araddr,
  input   logic [2:0]             s00_axil_arprot,
  input   logic                   s00_axil_arvalid,
  output  logic                   s00_axil_arready,
  output  logic [DATA_WIDTH-1:0]  s00_axil_rdata,
  output  logic [1:0]             s00_axil_rresp,
  output  logic                   s00_axil_rvalid,
  input   logic                   s00_axil_rready
);

  // Crossbar signals
  logic [ADDR_WIDTH-1:0]  gpu_mstr_axil_awaddr;
  logic [2:0]             gpu_mstr_axil_awprot;
  logic                   gpu_mstr_axil_awvalid;
  logic                   gpu_mstr_axil_awready;
  logic [DATA_WIDTH-1:0]  gpu_mstr_axil_wdata;
  logic [STRB_WIDTH-1:0]  gpu_mstr_axil_wstrb;
  logic                   gpu_mstr_axil_wvalid;
  logic                   gpu_mstr_axil_wready;
  logic [1:0]             gpu_mstr_axil_bresp;
  logic                   gpu_mstr_axil_bvalid;
  logic                   gpu_mstr_axil_bready;
  logic [ADDR_WIDTH-1:0]  gpu_mstr_axil_araddr;
  logic [2:0]             gpu_mstr_axil_arprot;
  logic                   gpu_mstr_axil_arvalid;
  logic                   gpu_mstr_axil_arready;
  logic [DATA_WIDTH-1:0]  gpu_mstr_axil_rdata;
  logic [1:0]             gpu_mstr_axil_rresp;
  logic                   gpu_mstr_axil_rvalid;
  logic                   gpu_mstr_axil_rready;

  logic [ADDR_WIDTH-1:0]  gpu_ctrl_axil_awaddr;
  logic [2:0]             gpu_ctrl_axil_awprot;
  logic                   gpu_ctrl_axil_awvalid;
  logic                   gpu_ctrl_axil_awready;
  logic [DATA_WIDTH-1:0]  gpu_ctrl_axil_wdata;
  logic [STRB_WIDTH-1:0]  gpu_ctrl_axil_wstrb;
  logic                   gpu_ctrl_axil_wvalid;
  logic                   gpu_ctrl_axil_wready;
  logic [1:0]             gpu_ctrl_axil_bresp;
  logic                   gpu_ctrl_axil_bvalid;
  logic                   gpu_ctrl_axil_bready;
  logic [ADDR_WIDTH-1:0]  gpu_ctrl_axil_araddr;
  logic [2:0]             gpu_ctrl_axil_arprot;
  logic                   gpu_ctrl_axil_arvalid;
  logic                   gpu_ctrl_axil_arready;
  logic [DATA_WIDTH-1:0]  gpu_ctrl_axil_rdata;
  logic [1:0]             gpu_ctrl_axil_rresp;
  logic                   gpu_ctrl_axil_rvalid;
  logic                   gpu_ctrl_axil_rready;

  logic [ADDR_WIDTH-1:0]  ram_axil_awaddr ;
  logic [2:0]             ram_axil_awprot ;
  logic                   ram_axil_awvalid;
  logic                   ram_axil_awready;
  logic [DATA_WIDTH-1:0]  ram_axil_wdata  ;
  logic [STRB_WIDTH-1:0]  ram_axil_wstrb  ;
  logic                   ram_axil_wvalid ;
  logic                   ram_axil_wready ;
  logic [1:0]             ram_axil_bresp  ;
  logic                   ram_axil_bvalid ;
  logic                   ram_axil_bready ;
  logic [ADDR_WIDTH-1:0]  ram_axil_araddr ;
  logic [2:0]             ram_axil_arprot ;
  logic                   ram_axil_arvalid;
  logic                   ram_axil_arready;
  logic [DATA_WIDTH-1:0]  ram_axil_rdata  ;
  logic [1:0]             ram_axil_rresp  ;
  logic                   ram_axil_rvalid ;
  logic                   ram_axil_rready ;

  /*
   * AXI4-Lite Crossbar
   */
  axil_crossbar_wrap_2x2 crossbar_bus_inst (
    .clk(clk),
    .rst(reset),

    // crossbar slave interface s00 should be exported
    .s00_axil_awaddr    (s00_axil_awaddr),
    .s00_axil_awprot    (s00_axil_awprot),
    .s00_axil_awvalid   (s00_axil_awvalid),
    .s00_axil_awready   (s00_axil_awready),
    .s00_axil_wdata     (s00_axil_wdata),
    .s00_axil_wstrb     (s00_axil_wstrb),
    .s00_axil_wvalid    (s00_axil_wvalid),
    .s00_axil_wready    (s00_axil_wready),
    .s00_axil_bresp     (s00_axil_bresp),
    .s00_axil_bvalid    (s00_axil_bvalid),
    .s00_axil_bready    (s00_axil_bready),
    .s00_axil_araddr    (s00_axil_araddr),
    .s00_axil_arprot    (s00_axil_arprot),
    .s00_axil_arvalid   (s00_axil_arvalid),
    .s00_axil_arready   (s00_axil_arready),
    .s00_axil_rdata     (s00_axil_rdata),
    .s00_axil_rresp     (s00_axil_rresp),
    .s00_axil_rvalid    (s00_axil_rvalid),
    .s00_axil_rready    (s00_axil_rready),

    .s01_axil_awaddr    (gpu_mstr_axil_awaddr),
    .s01_axil_awprot    (gpu_mstr_axil_awprot),
    .s01_axil_awvalid   (gpu_mstr_axil_awvalid),
    .s01_axil_awready   (gpu_mstr_axil_awready),
    .s01_axil_wdata     (gpu_mstr_axil_wdata),
    .s01_axil_wstrb     (gpu_mstr_axil_wstrb),
    .s01_axil_wvalid    (gpu_mstr_axil_wvalid),
    .s01_axil_wready    (gpu_mstr_axil_wready),
    .s01_axil_bresp     (gpu_mstr_axil_bresp),
    .s01_axil_bvalid    (gpu_mstr_axil_bvalid),
    .s01_axil_bready    (gpu_mstr_axil_bready),
    .s01_axil_araddr    (gpu_mstr_axil_araddr),
    .s01_axil_arprot    (gpu_mstr_axil_arprot),
    .s01_axil_arvalid   (gpu_mstr_axil_arvalid),
    .s01_axil_arready   (gpu_mstr_axil_arready),
    .s01_axil_rdata     (gpu_mstr_axil_rdata),
    .s01_axil_rresp     (gpu_mstr_axil_rresp),
    .s01_axil_rvalid    (gpu_mstr_axil_rvalid),
    .s01_axil_rready    (gpu_mstr_axil_rready),

    .m00_axil_awaddr    (ram_axil_awaddr),
    .m00_axil_awprot    (ram_axil_awprot),
    .m00_axil_awvalid   (ram_axil_awvalid),
    .m00_axil_awready   (ram_axil_awready),
    .m00_axil_wdata     (ram_axil_wdata),
    .m00_axil_wstrb     (ram_axil_wstrb),
    .m00_axil_wvalid    (ram_axil_wvalid),
    .m00_axil_wready    (ram_axil_wready),
    .m00_axil_bresp     (ram_axil_bresp),
    .m00_axil_bvalid    (ram_axil_bvalid),
    .m00_axil_bready    (ram_axil_bready),
    .m00_axil_araddr    (ram_axil_araddr),
    .m00_axil_arprot    (ram_axil_arprot),
    .m00_axil_arvalid   (ram_axil_arvalid),
    .m00_axil_arready   (ram_axil_arready),
    .m00_axil_rdata     (ram_axil_rdata),
    .m00_axil_rresp     (ram_axil_rresp),
    .m00_axil_rvalid    (ram_axil_rvalid),
    .m00_axil_rready    (ram_axil_rready),

    .m01_axil_awaddr    (gpu_ctrl_axil_awaddr),
    .m01_axil_awprot    (gpu_ctrl_axil_awprot),
    .m01_axil_awvalid   (gpu_ctrl_axil_awvalid),
    .m01_axil_awready   (gpu_ctrl_axil_awready),
    .m01_axil_wdata     (gpu_ctrl_axil_wdata),
    .m01_axil_wstrb     (gpu_ctrl_axil_wstrb),
    .m01_axil_wvalid    (gpu_ctrl_axil_wvalid),
    .m01_axil_wready    (gpu_ctrl_axil_wready),
    .m01_axil_bresp     (gpu_ctrl_axil_bresp),
    .m01_axil_bvalid    (gpu_ctrl_axil_bvalid),
    .m01_axil_bready    (gpu_ctrl_axil_bready),
    .m01_axil_araddr    (gpu_ctrl_axil_araddr),
    .m01_axil_arprot    (gpu_ctrl_axil_arprot),
    .m01_axil_arvalid   (gpu_ctrl_axil_arvalid),
    .m01_axil_arready   (gpu_ctrl_axil_arready),
    .m01_axil_rdata     (gpu_ctrl_axil_rdata),
    .m01_axil_rresp     (gpu_ctrl_axil_rresp),
    .m01_axil_rvalid    (gpu_ctrl_axil_rvalid),
    .m01_axil_rready    (gpu_ctrl_axil_rready)

  );

  /*
   * AXI4-Lite RAM
   */
  axil_ram #(
    .DATA_WIDTH(32),
    .ADDR_WIDTH(16)
  ) axil_ram0 (
    .clk              (clk),
    .rst              (reset),
    .s_axil_awaddr    (ram_axil_awaddr[15:0]),
    .s_axil_awprot    (ram_axil_awprot),
    .s_axil_awvalid   (ram_axil_awvalid),
    .s_axil_awready   (ram_axil_awready),
    .s_axil_wdata     (ram_axil_wdata),
    .s_axil_wstrb     (ram_axil_wstrb),
    .s_axil_wvalid    (ram_axil_wvalid),
    .s_axil_wready    (ram_axil_wready),
    .s_axil_bresp     (ram_axil_bresp),
    .s_axil_bvalid    (ram_axil_bvalid),
    .s_axil_bready    (ram_axil_bready),
    .s_axil_araddr    (ram_axil_araddr[15:0]),
    .s_axil_arprot    (ram_axil_arprot),
    .s_axil_arvalid   (ram_axil_arvalid),
    .s_axil_arready   (ram_axil_arready),
    .s_axil_rdata     (ram_axil_rdata),
    .s_axil_rresp     (ram_axil_rresp),
    .s_axil_rvalid    (ram_axil_rvalid),
    .s_axil_rready    (ram_axil_rready)
  );

  gpu gpu0 (
    .clk                  (clk),
    .reset                (reset),
    .mstr_axi_awvalid_o   (gpu_mstr_axil_awvalid),
    .mstr_axi_awready_i   (gpu_mstr_axil_awready),
    .mstr_axi_awaddr_o    (gpu_mstr_axil_awaddr),
    .mstr_axi_awprot_o    (gpu_mstr_axil_awprot),
    .mstr_axi_wvalid_o    (gpu_mstr_axil_wvalid),
    .mstr_axi_wready_i    (gpu_mstr_axil_wready),
    .mstr_axi_wdata_o     (gpu_mstr_axil_wdata),
    .mstr_axi_wstrb_o     (gpu_mstr_axil_wstrb),
    .mstr_axi_bvalid_i    (gpu_mstr_axil_bvalid),
    .mstr_axi_bresp_i     (gpu_mstr_axil_bresp),
    .mstr_axi_bready_o    (gpu_mstr_axil_bready),
    .mstr_axi_arvalid_o   (gpu_mstr_axil_arvalid),
    .mstr_axi_arready_i   (gpu_mstr_axil_arready),
    .mstr_axi_araddr_o    (gpu_mstr_axil_araddr),
    .mstr_axi_arprot_o    (gpu_mstr_axil_arprot),
    .mstr_axi_rvalid_i    (gpu_mstr_axil_rvalid),
    .mstr_axi_rready_o    (gpu_mstr_axil_rready),
    .mstr_axi_rdata_i     (gpu_mstr_axil_rdata),
    .mstr_axi_rresp_i     (gpu_mstr_axil_rresp),

    .ctrl_axi_awvalid_i   (gpu_ctrl_axil_awvalid),
    .ctrl_axi_awready_o   (gpu_ctrl_axil_awready),
    .ctrl_axi_awaddr_i    (gpu_ctrl_axil_awaddr),
    .ctrl_axi_awprot_i    (gpu_ctrl_axil_awprot),
    .ctrl_axi_wvalid_i    (gpu_ctrl_axil_wvalid),
    .ctrl_axi_wready_o    (gpu_ctrl_axil_wready),
    .ctrl_axi_wdata_i     (gpu_ctrl_axil_wdata),
    .ctrl_axi_wstrb_i     (gpu_ctrl_axil_wstrb),
    .ctrl_axi_bvalid_o    (gpu_ctrl_axil_bvalid),
    .ctrl_axi_bresp_o     (gpu_ctrl_axil_bresp),
    .ctrl_axi_bready_i    (gpu_ctrl_axil_bready),
    .ctrl_axi_arvalid_i   (gpu_ctrl_axil_arvalid),
    .ctrl_axi_arready_o   (gpu_ctrl_axil_arready),
    .ctrl_axi_araddr_i    (gpu_ctrl_axil_araddr),
    .ctrl_axi_arprot_i    (gpu_ctrl_axil_arprot),
    .ctrl_axi_rvalid_o    (gpu_ctrl_axil_rvalid),
    .ctrl_axi_rready_i    (gpu_ctrl_axil_rready),
    .ctrl_axi_rdata_o     (gpu_ctrl_axil_rdata),
    .ctrl_axi_rresp_o     (gpu_ctrl_axil_rresp)
  );
endmodule
