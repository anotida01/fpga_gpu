

module avlmm_ctrl_slave (
  input  logic clk, reset,

  // Avalon MM Slave port
  input  logic [ 3:0] address,
  input  logic [31:0] writedata,
  input  logic [ 0:0] write,
  input  logic [ 0:0] read,
  input  logic [ 3:0] byteenable,
  output logic [31:0] readdata,
  output logic [ 0:0] waitrequest,

  // control signals to gpu
  output logic [ 0:0] start_o,

  // control signals from gpu
  input  logic [ 0:0] ready_i,

  // to avlmm DMA master
  output logic [31:0] mem_offset_addr_o

);

  logic regf_start;
  logic regf_valid_p1;
  logic gpu_sm_en_p1;
  logic en_p0;
  logic en_p1;
  logic [31:0] writedata_p0;
  logic [ 2:0] addr_p0;
  
  // register_file
  gpu_ctrl_regfile regf0 (
    .clk, .reset,
    .en_p0_i        (en_p0),
    .addr_p0_i      (addr_p0),
    .writedata_p0_i (writedata_p0),
    .en_p1_i        (en_p1),
    .addr_p1_i      (address),
    .writedata_p1_i (writedata),
    .readdata_p1_o  (readdata),

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
    .en_p1_o        (gpu_sm_en_p1)
  );

  // bus facing state machine
  bus_sm bus_sm0 (
    .clk, .reset,
    .bus_write        (write),
    .bus_read         (read),
    .bus_waitrequest  (waitrequest),
    .regf_valid_o     (regf_valid_p1)
  );
  
  assign en_p1 = regf_valid_p1 && gpu_sm_en_p1;

endmodule

module gpu_sm (
  input  logic [ 0:0] clk, reset,
  input  logic [ 0:0] regf_start_i,
  input  logic [ 0:0] gpu_ready_i,
  output logic [ 0:0] gpu_start_o,
  output logic [ 0:0] en_p0_o,
  output logic [ 0:0] en_p1_o,
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


module bus_sm (
  input  logic [ 0:0] clk, reset,
  input  logic [ 0:0] bus_write,
  input  logic [ 0:0] bus_read,
  output logic [ 0:0] bus_waitrequest,
  output logic [ 0:0] regf_valid_o
);
    
  typedef enum logic [1:0] { 
    RESET,
    BUS_IDLE,
    READ_REQ,
    WRITE_REQ
    // IO_REQ
  } state_e;

  state_e state, next_state;
  always_ff @( posedge clk ) begin : state_logic
    if (reset) state <= RESET;
    else state <= next_state;
  end

  always_comb begin

    bus_waitrequest = 1;
    regf_valid_o = 0;
    
    case ({state})
    
      RESET : next_state = BUS_IDLE;

      BUS_IDLE : begin
        bus_waitrequest = 1;
        if (bus_read)
          next_state = READ_REQ;
        else if (bus_write)
          next_state = WRITE_REQ;
        else
          next_state = BUS_IDLE;
      end
 
      READ_REQ : begin
        bus_waitrequest = 0;
        next_state = BUS_IDLE;
      end

      WRITE_REQ : begin
        bus_waitrequest = 0;
        regf_valid_o = 1; // enable writing. may be blocked by GPU SM
        next_state = BUS_IDLE;
      end

      default: next_state = RESET;

    endcase

  end
endmodule


module gpu_ctrl_regfile (
  input  logic clk, reset,

  // port 0
  input  logic [ 0:0] en_p0_i,
  input  logic [ 2:0] addr_p0_i,
  input  logic [31:0] writedata_p0_i,
  output logic [31:0] readdata_p0_o,

  // port 1
  input  logic [ 0:0] en_p1_i,
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
  always_ff @( posedge clk ) begin
    if (reset) begin
      readdata_p0_o <= 32'd0;
      readdata_p1_o <= 32'd0;
    end else begin

      if (addr_p0_i < NUM_REGS)
        readdata_p0_o <= registers[addr_p0_i];
      else
        readdata_p0_o <= 32'd0;

      if (addr_p1_i < NUM_REGS)
        readdata_p1_o <= registers[addr_p1_i];
      else
        readdata_p1_o <= 32'd0;

    end
  end

  // Write operations for Port 1 and Port 2
  always_ff @( posedge clk ) begin
    if (reset)
      for (int i = 0; i < NUM_REGS; i++) registers[i] <= 32'd0;
    else begin

      if (en_p0_i && (addr_p0_i < NUM_REGS)) begin
        registers[addr_p0_i] <= writedata_p0_i;
      end

      if (en_p1_i && (addr_p1_i < NUM_REGS)) begin
        registers[addr_p1_i] <= writedata_p1_i;
      end

    end
  end

endmodule

