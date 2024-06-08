`timescale 1ps / 1ps

`define CPU   $root.tb.dut.cpu_mm_master_bfm
`define CLK   $root.tb.dut.clock_source_0
`define RST   $root.tb.dut.reset_source_0


module test_program ();

  import verbosity_pkg::*;
  import avalon_mm_pkg::*;

//---------------------------------------------------
// Constants
//---------------------------------------------------
   localparam ADDR_W                   = 32;
            
   localparam SYMBOL_W                 = 8;
   localparam NUM_SYMBOLS              = 4;
   localparam DATA_W                   = NUM_SYMBOLS * SYMBOL_W;
            
   localparam BURST_W                  = 4;
   localparam MAX_BURST                = 8;
   
  //  localparam SLAVE_SPAN               = 32'h1000;
   
   localparam MAX_COMMAND_IDLE         = 5;
   localparam MAX_COMMAND_BACKPRESSURE = 2;
   localparam MAX_DATA_IDLE            = 3;

   localparam GPU_CTRL_BASE_ADDR = 32'h0400_0000;

//---------------------------------------------------
// Data structures
//---------------------------------------------------
   typedef logic [BURST_W-1:0]      Burstcount;

   typedef enum bit
   {
       WRITE = 0,
       READ  = 1
   } Transaction;
   
   typedef enum bit
   {
       NOBURST = 0,
       BURST   = 1
   } Burstmode;

   typedef struct 
   {
       Transaction                  trans;
       Burstcount                   burstcount;
       logic [ADDR_W-1: 0]          addr;
       logic [DATA_W-1:0]           data       [MAX_BURST-1:0];
       logic [NUM_SYMBOLS-1:0]      byteenable [MAX_BURST-1:0];
       bit [31:0]                   cmd_delay;
       bit [31:0]                   data_idles [MAX_BURST-1:0];
   } Command;

   typedef struct
   {
      Burstcount                    burstcount;
      logic [DATA_W-1:0]            data     [MAX_BURST-1:0];
      bit [31:0]                    latency  [MAX_BURST-1:0];
   } Response;

  // master command queue
  Command  write_command_queue_master[1][$];
  Command  read_command_queue_master[1][$];

  Command cmd;
  Response rsp;
  int data;
  int cpu_mem [2097152]; // 64MiB
  // int dma_out_mem [2097152];

  wire clk;
  assign clk = $root.tb.dut.clock_source_0_clk_clk;

  wire reset;
  assign reset = $root.tb.dut.rst_controller_reset_out_reset;

  initial begin

    @(negedge reset)
    @(posedge clk)
    
    // cpu loads gpu mem with image to
    $readmemh("memh/box.memh", cpu_mem);

    for (integer i = 0; i < 272; i++) begin
      cmd = create_command(.trans(WRITE), .burstmode(NOBURST), .addr(32'h0 + (4*i)), .data(cpu_mem[i]));
      queue_command(cmd);
      wait_for_write_rsp();
    end

    // instruct the gpu to start using the CPU
    cmd = create_command(.trans(WRITE), .burstmode(NOBURST), .addr(GPU_CTRL_BASE_ADDR), .data(32'h1));
    queue_command(cmd);
    wait_for_write_rsp();

    repeat (100) @(posedge clk);

    // read gpu status and wait for it to finish
    forever begin

      cmd = create_command(.trans(READ), .burstmode(NOBURST), .addr(GPU_CTRL_BASE_ADDR), .data(32'h1));
      queue_command(cmd);
      wait_for_read_rsp(data);

      if (data == 32'd0) break;

    end

    #500ns;

    $stop;

  end


  function automatic Command create_command (
    Transaction    trans,
    Burstmode      burstmode,
    int            addr,
    int            data
  );

    Command cmd;
    
    if (burstmode == BURST) begin
        cmd.burstcount             = randomize_burstcount();
    end else begin
        cmd.burstcount             = 1;
    end
    
    cmd.trans                  = trans;
    cmd.addr                   = addr;
    cmd.cmd_delay              = $urandom_range(0, MAX_COMMAND_IDLE);
    
    if (trans == WRITE) begin
        for (int i = 0; i < cmd.burstcount; i++) begin
          cmd.data[i]          = data;
          cmd.byteenable[i]    = {NUM_SYMBOLS{1'b1}};
          cmd.data_idles[i]    = $urandom_range(0, MAX_DATA_IDLE);
        end
    end else begin
        cmd.data_idles[0]       = $urandom_range(0, MAX_DATA_IDLE);
    end
    
    return cmd;   
  endfunction

  task automatic configure_and_push_command_to_master(Command cmd);
    `CPU.set_command_address(cmd.addr);
    `CPU.set_command_burst_count(cmd.burstcount);
    `CPU.set_command_burst_size(cmd.burstcount);
    `CPU.set_command_init_latency(cmd.cmd_delay);

    if (cmd.trans == WRITE) begin
      `CPU.set_command_request(REQ_WRITE);
      for (int i = 0; i < cmd.burstcount; i++) begin
        `CPU.set_command_data(cmd.data[i], i);
        `CPU.set_command_byte_enable(cmd.byteenable[i], i);
        `CPU.set_command_idle(cmd.data_idles[i], i);
      end
    end else begin
        `CPU.set_command_request(REQ_READ);
        `CPU.set_command_idle(cmd.data_idles[0], 0);
    end
      `CPU.push_command();
  endtask

  task automatic queue_command (
    Command  cmd,
    int      master_id = 0
  );
    
    save_command_master(cmd, master_id);
    configure_and_push_command_to_master(cmd);
    // $display("Queued Command for CPU BFM - trans: %01d, addr: 0x%08x, data: 0x%08x", cmd.trans, cmd.addr, cmd.data[0]);
  endtask

  task automatic save_command_master( 
      Command  cmd,
      int      master_id
   );

    if (cmd.trans == WRITE) begin
      write_command_queue_master[master_id].push_back(cmd);
    end else begin
      read_command_queue_master[master_id].push_back(cmd);
    end
  endtask

  function automatic Burstcount randomize_burstcount ();
    
    Burstcount burstcount;
    
    burstcount = $urandom_range(1, MAX_BURST);
    return burstcount;
  endfunction


  function automatic Response get_response_from_cpu_bfm();
    Response rsp;

    `CPU.pop_response();
    rsp.burstcount    = `CPU.get_response_burst_size();
    for (int i = 0; i < rsp.burstcount; i++) begin
        rsp.data[i]    = `CPU.get_response_data(i);
    end

    // $display("Response from CPU BFM - data: 0x%08x", rsp.data[0]);

    return rsp;
  endfunction

  task wait_for_write_rsp;

    Response rsp;
    int addr, data, num_rsp;

      forever begin
        num_rsp = `CPU.get_write_response_queue_size();
        if (num_rsp != 0) break;
        else @(posedge clk);
      end

      rsp = get_response_from_cpu_bfm();
      addr = `CPU.get_response_address();
      data = `CPU.get_response_data(0);

      $display("Write Response from CPU BFM - addr: 0x%08x, data: 0x%08x", addr, data);

  endtask

  task wait_for_read_rsp(output int data);

    Response rsp;
    int addr, num_rsp;

    forever begin
      num_rsp = `CPU.get_read_response_queue_size();
      if (num_rsp != 0) break;
      else @(posedge clk);
    end

    rsp = get_response_from_cpu_bfm();
    addr = `CPU.get_response_address();
    data = `CPU.get_response_data(0);

    // $display("Read Response from CPU BFM - addr: 0x%08x, data: 0x%08x", addr, data);

  endtask


endmodule
