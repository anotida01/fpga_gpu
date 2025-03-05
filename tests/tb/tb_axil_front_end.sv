

// simulate and test the AXI Lite front end bus interface by itself
module tb_axil_front_end ();

  typedef struct {
    int unsigned req_addr;
    int unsigned resp_data;
  } dma_tx_t;

  dma_tx_t dma_tx_q[$];

  int unsigned mem [int]; // sparse mem model
  bit clk_enable = 1;

  // AXI Intf
  logic              mstr_axi_awvalid_o;
  logic              mstr_axi_awready_i;
  logic [31:0]       mstr_axi_awaddr_o;
  logic [ 2:0]       mstr_axi_awprot_o;
  logic              mstr_axi_wvalid_o;
  logic              mstr_axi_wready_i;
  logic [31:0]       mstr_axi_wdata_o;
  logic [32/8-1:0]   mstr_axi_wstrb_o;
  logic              mstr_axi_bvalid_i;
  logic [1:0]        mstr_axi_bresp_i;
  logic              mstr_axi_bready_o;
  logic              mstr_axi_arvalid_o;
  logic              mstr_axi_arready_i;
  logic [31:0]       mstr_axi_araddr_o;
  logic [ 2:0]       mstr_axi_arprot_o;
  logic              mstr_axi_rvalid_i;
  logic              mstr_axi_rready_o;
  logic [31:0]       mstr_axi_rdata_i;
  logic [ 1:0]       mstr_axi_rresp_i;

  // AXI CTRL intf
  logic              ctrl_axi_awvalid_i;// AW
  logic              ctrl_axi_awready_o;
  logic [31:0]       ctrl_axi_awaddr_i;
  logic [ 2:0]       ctrl_axi_awprot_i;
  logic              ctrl_axi_wvalid_i;// W
  logic              ctrl_axi_wready_o;
  logic [31:0]       ctrl_axi_wdata_i;
  logic [32/8-1:0]   ctrl_axi_wstrb_i;
  logic              ctrl_axi_bvalid_o;// B
  logic [1:0]        ctrl_axi_bresp_o;
  logic              ctrl_axi_bready_i;
  logic              ctrl_axi_arvalid_i;// AR
  logic              ctrl_axi_arready_o;
  logic [31:0]       ctrl_axi_araddr_i;
  logic [ 2:0]       ctrl_axi_arprot_i;
  logic              ctrl_axi_rvalid_o;// R
  logic              ctrl_axi_rready_i;
  logic [31:0]       ctrl_axi_rdata_o;
  logic [ 1:0]       ctrl_axi_rresp_o;

  // other DUT signals
  logic        gpu_dma_ready;
  logic        gpu_dma_valid;
  logic [31:0] gpu_dma_address;
  logic        gpu_ctrl_done;

  logic         gpu_start;
  logic         dma_ready;
  logic         dma_valid;
  logic [31:0]  dma_out;


  logic clk, reset;


  axil_gpu_front_end DUT (
    .clk                (clk), 
    .reset              (reset),
    
    // DMA AXI Master Interface
    .mstr_axi_awvalid_o,
    .mstr_axi_awready_i,
    .mstr_axi_awaddr_o ,
    .mstr_axi_awprot_o ,
    .mstr_axi_wvalid_o ,
    .mstr_axi_wready_i ,
    .mstr_axi_wdata_o  ,
    .mstr_axi_wstrb_o  ,
    .mstr_axi_bvalid_i ,
    .mstr_axi_bresp_i  ,
    .mstr_axi_bready_o ,
    .mstr_axi_arvalid_o,
    .mstr_axi_arready_i,
    .mstr_axi_araddr_o ,
    .mstr_axi_arprot_o ,
    .mstr_axi_rvalid_i ,
    .mstr_axi_rready_o ,
    .mstr_axi_rdata_i  ,
    .mstr_axi_rresp_i  ,

    .ctrl_axi_awvalid_i,
    .ctrl_axi_awready_o,
    .ctrl_axi_awaddr_i,
    .ctrl_axi_awprot_i,
    .ctrl_axi_wvalid_i,
    .ctrl_axi_wready_o,
    .ctrl_axi_wdata_i,
    .ctrl_axi_wstrb_i,
    .ctrl_axi_bvalid_o,
    .ctrl_axi_bresp_o,
    .ctrl_axi_bready_i,
    .ctrl_axi_arvalid_i,
    .ctrl_axi_arready_o,
    .ctrl_axi_araddr_i,
    .ctrl_axi_arprot_i,
    .ctrl_axi_rvalid_o,
    .ctrl_axi_rready_i,
    .ctrl_axi_rdata_o,
    .ctrl_axi_rresp_o,

    // from gpu
    .gpu_dma_ready,
    .gpu_dma_valid,
    .gpu_dma_address,
    .gpu_ctrl_done,

    // to gpu
    .gpu_start,
    .dma_ready,
    .dma_valid,
    .dma_out

  );


  // any power on reset functionality should go here
  initial begin : power_on_reset
    reset = 0;

    // these are under TB control - need to driven by responders!
    mstr_axi_awready_i = 0;
    mstr_axi_wready_i = 0;
    mstr_axi_bvalid_i = 0;
    mstr_axi_bresp_i = 0;
    mstr_axi_arready_i = 0;
    mstr_axi_rvalid_i = 0;
    mstr_axi_rdata_i = 0;
    mstr_axi_rresp_i = 0;

    ctrl_axi_awvalid_i = 0;
    ctrl_axi_awaddr_i = 0;
    ctrl_axi_awprot_i = 0;
    ctrl_axi_wvalid_i = 0;
    ctrl_axi_wdata_i = 0;
    ctrl_axi_wstrb_i = 0;
    ctrl_axi_bready_i = 0;
    ctrl_axi_arvalid_i = 0;
    ctrl_axi_araddr_i = 0;
    ctrl_axi_arprot_i = 0;
    ctrl_axi_rready_i = 0;

    gpu_dma_ready = 0;
    gpu_dma_valid = 0;
    gpu_dma_address = 0;
    gpu_ctrl_done = 0;
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


  // responds to AXI reads and writes from the DUT
  // todo: this responder does not support receiving the data before the address
  // todo: this responder also has another major issue where it needs to be able to combinationally detect a loss of the ax_ready signal
  // i.e just because ax_ready is asserted in this cc, doesn't mean it will be asserted in the next cc
  task start_axi_bus_responder();
    fork
      forever begin
        int aw_local[$], w_local[$];
        int ar_local[$];
        int bresp_local[$];

        // Wait for a valid AXI transaction
        wait_clk();

        // ********** WRITE RESPONDER ********** // 
        // ready for write address and data
        mstr_axi_awready_i <= 1;
        mstr_axi_wready_i <= 1;

        if (mstr_axi_awvalid_o)
          aw_local.push_back(mstr_axi_awaddr_o);

        if (mstr_axi_wvalid_o)
          w_local.push_back(mstr_axi_wdata_o);

        // if we have both address and data, write to sparse mem
        if ( (aw_local.size() != 0) && (w_local.size() != 0) )
          if (aw_local.size() == w_local.size())
            foreach(aw_local[i]) begin
              mem[aw_local[i]] = w_local[i]; // assumes order is the same!
              bresp_local.push_back(0); // todo: assumes OK!
              aw_local.delete(i);
              w_local.delete(i);
            end

        // todo: this is kinda buggy since it's unware of what i_axi_bready will be in the next cc
        // so this should probably be combinational
        if ( mstr_axi_bready_o && (bresp_local.size() != 0) ) begin
          mstr_axi_bvalid_i <= 1; // signal completion
          mstr_axi_bresp_i <= bresp_local[0]; // respond to oldest write
          bresp_local.pop_front();
        end else begin
          mstr_axi_bvalid_i <= 0;
          mstr_axi_bresp_i <= 0;
        end

        // ********** READ RESPONDER ********** // 
        
        mstr_axi_arready_i <= 1; // ready for read

        if (mstr_axi_arvalid_o)
          ar_local.push_back(mstr_axi_araddr_o);

        // Provide data and status when read request arrives
        // todo: this also assumes that things will still be ready in the next cc
        // we need to add logic that holds valid signals when ready transition to not ready
        if ( mstr_axi_rready_o && (ar_local.size() != 0) ) begin
          mstr_axi_rvalid_i <= 1;
          mstr_axi_rdata_i <= mem[ar_local[0]]; // Read from memory
          mstr_axi_rresp_i <= 2'b00; // OK response
          ar_local.pop_front();
        end else begin
          mstr_axi_rvalid_i <= 0;
          mstr_axi_rresp_i <= 2'b00; // OK response
        end
      end
    join_none
  endtask

  task axi_write(int unsigned addr, int unsigned data);
    logic [1:0] bresp_local;

    // drive address then drive data
    // todo: not sure if AXIL supports data before address
    wait_clk();
    ctrl_axi_awvalid_i <= 1;
    ctrl_axi_awaddr_i <= addr;
    do wait_clk(); while (!ctrl_axi_awready_o);
    ctrl_axi_awvalid_i <= 0;

    wait_clk();
    ctrl_axi_wvalid_i <= 1;
    ctrl_axi_wdata_i <= data;
    do wait_clk(); while (!ctrl_axi_wready_o);
    ctrl_axi_wvalid_i <= 0;

    // $display("waiting for bresp");
    ctrl_axi_bready_i <= 1;
    do wait_clk(); while (!ctrl_axi_bvalid_o);
    ctrl_axi_bready_i <= 0;

    bresp_local = ctrl_axi_bresp_o;
    $display($sformatf("Got BRESP: %x", bresp_local)); // todo: do something with this?
  endtask

  task axi_read(int unsigned addr, output int unsigned rdata);
    logic [1:0] rresp_local;

    // drive address
    wait_clk();
    ctrl_axi_araddr_i <= addr;
    ctrl_axi_arvalid_i <= 1;
    do wait_clk(); while (!ctrl_axi_arready_o);
    ctrl_axi_arvalid_i <= 0;

    // wait for resp
    wait_clk();
    ctrl_axi_rready_i <= 1;
    do wait_clk(); while (!ctrl_axi_rvalid_o);
    ctrl_axi_rready_i <= 0;

    rdata = ctrl_axi_rdata_o;
    rresp_local = ctrl_axi_rresp_o;

    $display($sformatf("Received RRESP: %x RDATA: %x", rresp_local, rdata));
  endtask

  // we need to be able to perform reads from gpu (driver)
  task gpu_read_req(int unsigned address);
    wait_clk();
    gpu_dma_address <= address;
    gpu_dma_valid <= 1;
    
    forever begin
      wait_clk();
      if (dma_ready) begin
        gpu_dma_valid <= 0;
        break;
      end
    end
  endtask

  // we also need to be able to monitor the responses going back to the gpu (monitor)
  task start_dma_tx_monitor();
    fork
      forever begin
        dma_tx_t tx;

        // capture request
        $display("[DMA_TX_MONITOR] - Waiting for address from GPU");
        do wait_clk(); while (!(gpu_dma_valid && dma_ready));
        tx.req_addr = gpu_dma_address;
        $display($sformatf("[DMA_TX_MONITOR] - Got address %X from GPU", tx.req_addr));

        // capture response
        $display("[DMA_TX_MONITOR] - Waiting for data resp from DMA");
        do wait_clk(); while (!(dma_valid && gpu_dma_ready));
        tx.resp_data = dma_out;
        $display($sformatf("[DMA_TX_MONITOR] - Got data %X from DMA", tx.resp_data));

        dma_tx_q.push_back(tx);

      end
    join_none
  endtask


endmodule
