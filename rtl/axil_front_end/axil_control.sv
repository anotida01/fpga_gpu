

module axil_ctrl_slave (
  input  logic clk, reset,

  // WB Slave port
  input  logic        i_wb_cyc,
  input  logic        i_wb_stb,
  input  logic        i_wb_we,
  input  logic [31:0] i_wb_addr,
  input  logic [31:0] i_wb_data,
  input  logic [ 3:0] i_wb_sel,
  output logic [31:0] o_wb_data,
  output logic        o_wb_ack,
  output logic        o_wb_stall,
  output logic        o_wb_err,

  // control signals to gpu
  output logic        start_o,

  // control signals from gpu
  input  logic        ready_i,

  // to avlmm DMA master
  output logic [31:0] mem_offset_addr_o

);

  logic regf_start;
  logic bus_sm_en_wr_p1;
  logic gpu_sm_en_wr_p1;
  logic en_p0;
  logic en_wr_p1;
  logic en_rd_p1;
  logic [31:0] writedata_p0;
  logic [ 2:0] addr_p0;
  
  // register_file
  gpu_ctrl_regfile regf0 (
    .clk, .reset,
    .rd_en_p0_i     (en_p0),
    .wr_en_p0_i     (1'h0), // gpu sm is readonly for now
    .addr_p0_i      (addr_p0),
    .writedata_p0_i (writedata_p0),

    .rd_en_p1_i     (en_rd_p1),
    .wr_en_p1_i     (en_wr_p1),
    .addr_p1_i      (i_wb_addr),
    .writedata_p1_i (i_wb_data),
    .readdata_p1_o  (o_wb_data),

    .regf_start,
    .mem_offset_addr_o
  );

  // gpu facing state machine
  gpu_sm gpu_sm0 (
    .clk, .reset,
    .regf_start_i   (regf_start),
    .gpu_ready_i    (ready_i),
    .gpu_start_o    (start_o),
    .en_p0_o        (en_p0),
    .writedata_p0_o (writedata_p0),
    .addr_p0_o      (addr_p0),
    .en_p1_o        (gpu_sm_en_wr_p1)
  );

  // bus facing state machine
  bus_sm bus_sm0 (
    .clk, .reset,
    .i_wb_cyc,
    .i_wb_stb,
    .i_wb_we,
    .i_wb_addr,
    .i_wb_sel,
    .o_wb_ack,
    .o_wb_stall,
    .o_wb_err,
    .regf_en_wr_port   (bus_sm_en_wr_p1),
    .regf_en_rd_port   (en_rd_p1)
  );
  
  assign en_wr_p1 = bus_sm_en_wr_p1 && gpu_sm_en_wr_p1;

endmodule

module gpu_sm (
  input  logic        clk, reset,
  input  logic        regf_start_i,
  input  logic        gpu_ready_i,
  output logic        gpu_start_o,
  output logic        en_p0_o,
  output logic        en_p1_o,
  output logic [31:0] writedata_p0_o,
  output logic [ 2:0] addr_p0_o
);

  typedef enum logic [2:0] { 
    RESET,
    IDLE,
    START,
    WAIT,
    DONE
  } state_e;

  state_e state, next_state;
  always_ff @( posedge clk ) begin : state_logic
    if (reset) state <= RESET;
    else state <= next_state;
  end

  always_comb begin : output_logic

    gpu_start_o = 0;
    en_p0_o = 0;
    en_p1_o = 1;
    writedata_p0_o = '0;
    addr_p0_o = '0;

    case ({state})
      RESET :  begin
        next_state = IDLE;
      end

      IDLE : begin
        if (regf_start_i) begin
          next_state = START;
        end else
          next_state = IDLE;
      end

      START : begin
        if (gpu_ready_i) begin
          gpu_start_o = 1;
          next_state = WAIT;
        end else 
          next_state = START;
      end

      WAIT : begin 
        // writes from CPU are blocked while GPU is processing an object
        // TODO: maybe add per register blocking here
        en_p1_o = 0;
        if (gpu_ready_i)
          next_state = DONE;
        else
          next_state = WAIT;
      end

      DONE : begin
        // clear start bit
        writedata_p0_o = '0;
        addr_p0_o = '0;
        en_p0_o = 1;
        next_state = IDLE;
      end

      default : next_state = RESET;
    endcase
  end
endmodule


// todo: we need to handle errors
module bus_sm (
  input  logic clk, reset,

  // WB Slave port
  input  logic        i_wb_cyc,
  input  logic        i_wb_stb,
  input  logic        i_wb_we,
  input  logic [31:0] i_wb_addr, // we may need this to signal decode errors
  input  logic [ 3:0] i_wb_sel,
  output logic        o_wb_ack,
  output logic        o_wb_stall,
  output logic        o_wb_err,
  
  output logic        regf_en_wr_port,
  output logic        regf_en_rd_port
);
    
  typedef enum logic [1:0] { 
    RESET,
    BUS_IDLE,
    ACK
  } state_e;

  state_e state, next_state;
  always_ff @( posedge clk ) begin : state_logic
    if (reset) state <= RESET;
    else state <= next_state;
  end

  always_comb begin

    regf_en_rd_port = 0;
    regf_en_wr_port = 0;
    o_wb_ack = 0;
    o_wb_stall = 0;
    o_wb_err = 0;
    
    case ({state})
    
      RESET : next_state = BUS_IDLE;

      BUS_IDLE : begin

        if (i_wb_cyc && i_wb_stb) begin // bus transaction has begun

          if (i_wb_we) begin // write req
            regf_en_wr_port = 1; // enables writing
            next_state = ACK;
          end else begin // read req
            regf_en_rd_port = 1; // enables writing
            next_state = ACK;
          end

        end else
          next_state = BUS_IDLE;

      end
 
      ACK      : begin

        if (i_wb_cyc) begin
          o_wb_ack = 1;
          next_state = BUS_IDLE;
        end else // todo: we should abort here? I guess just go back to IDLE?
          next_state = BUS_IDLE;

      end

      default: next_state = RESET;

    endcase

  end
endmodule


module gpu_ctrl_regfile (
  input  logic clk, reset,

  // port 0
  input  logic [ 0:0] wr_en_p0_i,
  input  logic [ 0:0] rd_en_p0_i,
  input  logic [ 2:0] addr_p0_i,
  input  logic [31:0] writedata_p0_i,
  output logic [31:0] readdata_p0_o,

  // port 1
  input  logic [ 0:0] wr_en_p1_i,
  input  logic [ 0:0] rd_en_p1_i,
  input  logic [ 3:0] addr_p1_i,
  input  logic [31:0] writedata_p1_i,
  output logic [31:0] readdata_p1_o,

  output logic [ 0:0] regf_start,
  output logic [31:0] mem_offset_addr_o

);

  logic gpu_reset_req;

  localparam NUM_REGS = 4;

  // Declare the register file
  logic [31:0] registers [NUM_REGS];

  assign regf_start         = registers[0][0];
  assign gpu_reset_req      = registers[0][1];
  assign mem_offset_addr_o  = registers[1];

  // Read operations for Port 1 and Port 2
  // todo: we need a read enable signal that's seperate from write enable
  always_ff @( posedge clk ) begin
    if (reset) begin
      readdata_p0_o <= 32'd0;
      readdata_p1_o <= 32'd0;
    end else begin

      if (rd_en_p0_i) begin
        if (addr_p0_i < NUM_REGS)
          readdata_p0_o <= registers[addr_p0_i];
        else
          readdata_p0_o <= 32'd0;
      end else
        readdata_p0_o <= readdata_p0_o;

      if (rd_en_p1_i) begin
        if (addr_p1_i < NUM_REGS)
          readdata_p1_o <= registers[addr_p1_i];
        else
          readdata_p1_o <= 32'd0;
      end else
        readdata_p1_o <= readdata_p1_o;

    end
  end

  // Write operations for Port 1 and Port 2
  always_ff @( posedge clk ) begin
    if (reset)
      for (int i = 0; i < NUM_REGS; i++) registers[i] <= 32'd0;
    else begin

      if (wr_en_p0_i && (addr_p0_i < NUM_REGS)) begin
        registers[addr_p0_i] <= writedata_p0_i;
      end

      if (wr_en_p1_i && (addr_p1_i < NUM_REGS)) begin
        registers[addr_p1_i] <= writedata_p1_i;
      end

    end
  end

endmodule