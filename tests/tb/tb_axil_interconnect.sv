

module tb_axil_interconnect ();

  // TB control variables
  bit clk_enable = 0;

  // DUT Signals
  logic clk, reset;

  // AXIL Slave Interface Signals
  logic [31:0] s00_axil_awaddr;
  logic [2:0] s00_axil_awprot;
  logic s00_axil_awvalid;
  logic s00_axil_awready;
  logic [31:0] s00_axil_wdata;
  logic [3:0] s00_axil_wstrb;
  logic s00_axil_wvalid;
  logic s00_axil_wready;
  logic [1:0] s00_axil_bresp;
  logic s00_axil_bvalid;
  logic s00_axil_bready;
  logic [31:0] s00_axil_araddr;
  logic [2:0] s00_axil_arprot;
  logic s00_axil_arvalid;
  logic s00_axil_arready;
  logic [31:0] s00_axil_rdata;
  logic [1:0] s00_axil_rresp;
  logic s00_axil_rvalid;
  logic s00_axil_rready;

  // Instantiate the Design Under Test (DUT)
  axil_sys_top dut (
    .clk(clk),
    .reset(reset),
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
    .s00_axil_rready    (s00_axil_rready)
  );

  // any power on reset functionality should go here
  initial begin : power_on_reset
    reset = 0;

    s00_axil_awvalid = 0;
    s00_axil_awaddr = 0;
    s00_axil_awprot = 0;
    s00_axil_wvalid = 0;
    s00_axil_wdata = 0;
    s00_axil_wstrb = 0;
    s00_axil_bready = 0;
    s00_axil_arvalid = 0;
    s00_axil_araddr = 0;
    s00_axil_arprot = 0;
    s00_axil_rready = 0;

  end : power_on_reset

  // Helper Functions
  task automatic wait_clk(int unsigned num_cycles = 1);
    repeat(num_cycles) @(posedge clk);
  endtask

  task start_clk(int clock_period);
    clk_enable = 1;
    clk <= 0;
    fork
      forever begin
        if (clk_enable) begin
          #(clock_period);
          clk <= ~clk;
        end else begin
          @(posedge clk_enable); // wait for clk enable
        end
      end
    join_none
  endtask

  task reset_dut;
    wait_clk();
      reset <= 1;
    wait_clk();
      reset <= 0;
  endtask

  task axi_write(int unsigned addr, int unsigned data);
    logic [1:0] bresp_local;

    // drive address then drive data
    // todo: not sure if AXIL supports data before address
    wait_clk();
    s00_axil_awvalid <= 1;
    s00_axil_awaddr <= addr;
    do wait_clk(); while (!s00_axil_awready);
    s00_axil_awvalid <= 0;

    wait_clk();
    s00_axil_wvalid <= 1;
    s00_axil_wdata <= data;
    do wait_clk(); while (!s00_axil_wready);
    s00_axil_wvalid <= 0;

    // $display("waiting for bresp");
    s00_axil_bready <= 1;
    do wait_clk(); while (!s00_axil_bvalid);
    s00_axil_bready <= 0;

    bresp_local = s00_axil_bresp;
    $display($sformatf("Got BRESP: %x", bresp_local)); // todo: do something with this?
  endtask

  task axi_read(int unsigned addr, output int unsigned rdata);
    logic [1:0] rresp_local;

    // drive address
    wait_clk();
    s00_axil_araddr <= addr;
    s00_axil_arvalid <= 1;
    do wait_clk(); while (!s00_axil_arready);
    s00_axil_arvalid <= 0;

    // wait for resp
    wait_clk();
    s00_axil_rready <= 1;
    do wait_clk(); while (!s00_axil_rvalid);
    s00_axil_rready <= 0;

    rdata = s00_axil_rdata;
    rresp_local = s00_axil_rresp;

    $display($sformatf("Received RRESP: %x RDATA: %x", rresp_local, rdata));
  endtask



endmodule