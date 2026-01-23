module tb_axil_slave;

  // Parameters
  localparam CLK_PERIOD = 10;
  logic [31:0] sparse_mem [0:255];

  // Signals
  reg          tb_clk;
  reg          tb_reset;
  reg  [31:0]  tb_s_axi_awaddr;
  reg  [2:0]   tb_s_axi_awprot;
  reg          tb_s_axi_awvalid;
  wire         tb_s_axi_awready;
  reg  [31:0]  tb_s_axi_wdata;
  reg  [3:0]   tb_s_axi_wstrb;
  reg          tb_s_axi_wvalid;
  wire         tb_s_axi_wready;
  wire [1:0]   tb_s_axi_bresp;
  wire         tb_s_axi_bvalid;
  reg          tb_s_axi_bready;
  reg  [31:0]  tb_s_axi_araddr;
  reg  [2:0]   tb_s_axi_arprot;
  reg          tb_s_axi_arvalid;
  wire         tb_s_axi_arready;
  wire [31:0]  tb_s_axi_rdata;
  wire [1:0]   tb_s_axi_rresp;
  wire         tb_s_axi_rvalid;
  reg          tb_s_axi_rready;

  logic        tb_o_wb_cyc;
  logic        tb_o_wb_stb;
  logic        tb_o_wb_we;
  logic [31:0] tb_o_wb_addr;
  logic [31:0] tb_o_wb_data;
  logic [31:0] tb_i_wb_data;
  logic [3:0]  tb_o_wb_sel;
  logic        tb_i_wb_ack;
  logic        tb_i_wb_stall;
  logic        tb_i_wb_err;

  wire tb_reset_n = ~tb_reset;

  // Instantiate the DUT
  axlite2wbsp dut (
    .i_clk          (tb_clk),
    .i_axi_reset_n  (tb_reset_n),
    .i_axi_awaddr   (tb_s_axi_awaddr),
    .i_axi_awprot   (tb_s_axi_awprot),
    .i_axi_awvalid  (tb_s_axi_awvalid),
    .o_axi_awready  (tb_s_axi_awready),
    .i_axi_wdata    (tb_s_axi_wdata),
    .i_axi_wstrb    (tb_s_axi_wstrb),
    .i_axi_wvalid   (tb_s_axi_wvalid),
    .o_axi_wready   (tb_s_axi_wready),
    .o_axi_bresp    (tb_s_axi_bresp),
    .o_axi_bvalid   (tb_s_axi_bvalid),
    .i_axi_bready   (tb_s_axi_bready),
    .i_axi_araddr   (tb_s_axi_araddr),
    .i_axi_arprot   (tb_s_axi_arprot),
    .i_axi_arvalid  (tb_s_axi_arvalid),
    .o_axi_arready  (tb_s_axi_arready),
    .o_axi_rdata    (tb_s_axi_rdata),
    .o_axi_rresp    (tb_s_axi_rresp),
    .o_axi_rvalid   (tb_s_axi_rvalid),
    .i_axi_rready   (tb_s_axi_rready),

    .o_reset        (tb_o_wb_reset),
    .o_wb_cyc       (tb_o_wb_cyc),
    .o_wb_stb       (tb_o_wb_stb),
    .o_wb_we        (tb_o_wb_we),
    .o_wb_addr      (tb_o_wb_addr),
    .o_wb_data      (tb_o_wb_data),
    .o_wb_sel       (tb_o_wb_sel),
    .i_wb_data      (tb_i_wb_data),
    .i_wb_ack       (tb_i_wb_ack),
    .i_wb_stall     (tb_i_wb_stall),
    .i_wb_err       (tb_i_wb_err)
  );

  // Clock generation
  initial begin
    tb_clk = 0;
    forever #(CLK_PERIOD/2) tb_clk = ~tb_clk;
  end

  // Reset generation
  initial begin
    tb_reset = 1;
    #(2*CLK_PERIOD);
    tb_reset = 0;
  end

  task wait_clk(int n = 1);
    repeat(n) @(posedge tb_clk);
  endtask

  // AXI-Lite read function
  task axi_lite_read(input [31:0] addr, output [31:0] data);
    begin
      wait_clk();
      tb_s_axi_araddr  <= addr;
      tb_s_axi_arprot  <= 3'b000;
      tb_s_axi_arvalid <= 1;
      tb_s_axi_rready  <= 1;

      // Wait for the read address to be accepted
      do wait_clk(); while (!tb_s_axi_arready);
      tb_s_axi_arvalid <= 0;

      // Wait for the read data to be valid
      do wait_clk(); while (!tb_s_axi_rvalid);
      // wait(tb_s_axi_rvalid);
      data = tb_s_axi_rdata;
      tb_s_axi_rready <= 0;
    end
  endtask

  // AXI-Lite write function
  task axi_lite_write(input [31:0] addr, input [31:0] data, input [3:0] strb = 'hF);
    begin
      wait_clk();

      tb_s_axi_awaddr  <= addr;
      tb_s_axi_awprot  <= 3'b000;
      tb_s_axi_awvalid <= 1;

      // Wait for the write address to be accepted
      do wait_clk(); while (!tb_s_axi_awready);
      tb_s_axi_awvalid <= 0;

      wait_clk(); // Allow one clock cycle for setup

      tb_s_axi_wdata   <= data;
      tb_s_axi_wstrb   <= strb;
      tb_s_axi_wvalid  <= 1;

      // Wait for the write data to be accepted
      do wait_clk(); while (!tb_s_axi_wready);
      tb_s_axi_wvalid <= 0;

      // Drive bready high to acknowledge the response and clear signals
      tb_s_axi_bready <= 1;
      do wait_clk(); while (!tb_s_axi_bvalid); // Wait for response valid

      $display("Write Response: %h", tb_s_axi_bresp);
      tb_s_axi_bready <= 0;

    end
  endtask

  // Wishbone responder task
  task start_wishbone_responder();
    integer i;
    fork
      begin
        // // Initialize sparse_mem
        // for (i = 0; i < 256; i = i + 1) begin
        //   sparse_mem[i] = 32'h0;
        // end

        // Wishbone response loop
        forever begin
          wait(tb_o_wb_cyc && tb_o_wb_stb);
          wait_clk();

          if (tb_o_wb_we) begin
            // Write operation
            if (tb_o_wb_sel[0]) sparse_mem[tb_o_wb_addr][7:0]   = tb_o_wb_data[7:0];
            if (tb_o_wb_sel[1]) sparse_mem[tb_o_wb_addr][15:8]  = tb_o_wb_data[15:8];
            if (tb_o_wb_sel[2]) sparse_mem[tb_o_wb_addr][23:16] = tb_o_wb_data[23:16];
            if (tb_o_wb_sel[3]) sparse_mem[tb_o_wb_addr][31:24] = tb_o_wb_data[31:24];
          end else begin
            // Read operation
            tb_i_wb_data = sparse_mem[tb_o_wb_addr];
          end

          // Acknowledge the transaction
          tb_i_wb_ack <= 1;
          wait_clk();
          tb_i_wb_ack <= 0;
        end
      end
    join_none
  endtask

  // Test sequence
  initial begin
    logic [31:0] read_data;

    // Initialize signals
    tb_s_axi_awaddr  = 0;
    tb_s_axi_awprot  = 0;
    tb_s_axi_awvalid = 0;
    tb_s_axi_wdata   = 0;
    tb_s_axi_wstrb   = 0;
    tb_s_axi_wvalid  = 0;
    tb_s_axi_bready  = 1;
    tb_s_axi_araddr  = 0;
    tb_s_axi_arprot  = 0;
    tb_s_axi_arvalid = 0;
    tb_s_axi_rready  = 1;
    tb_i_wb_ack      = 0;
    tb_i_wb_stall    = 0;
    tb_i_wb_err      = 0;
    tb_i_wb_data     = 0;

    // Wait for reset deassertion
    wait(!tb_reset);
    start_wishbone_responder();

    axi_lite_write('h0, 'h5a5a5a5a);
    axi_lite_write('h4, 'hdeadbeef);
    axi_lite_write('h8, 'ha5a5a5a5);

    // Perform an AXI-Lite read
    axi_lite_read(32'h00, read_data); assert (read_data == 'h5a5a5a5a);
    $display("Read data: %h", read_data);
    axi_lite_read(32'h04, read_data); assert (read_data == 'hdeadbeef);
    $display("Read data: %h", read_data);
    axi_lite_read(32'h08, read_data); assert (read_data == 'ha5a5a5a5);
    $display("Read data: %h", read_data);

    // Finish simulation
    $finish;
  end

endmodule
