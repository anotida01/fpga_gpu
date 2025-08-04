

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
  output logic [31:0] input_mem_offset_addr_o,
  output logic [31:0] output_mem_offset_addr_o,

  // irq signals to outside -- this might become just a general GPU IRQ
  output logic irq_gpu

);

  localparam NUM_REGS = 5;
  localparam ONES = 32'hFFFFFFFF;
  logic [31:0] regf_writemask [NUM_REGS];

  logic start_d;
  logic gpu_working;
  logic gpu_done;
  logic posedge_start_detected;

  // register writemasks
  generate
    genvar i;
    for (i = 0; i < NUM_REGS; i++) begin : gen_writemask
      if (i == 1)
        assign regf_writemask[i] = 32'h1;
      else
        assign regf_writemask[i] = ONES; // by default, no protected bits
    end
  endgenerate

  logic regf_start;
  logic irq_clr_gpu_done;
  logic irq_gpu_done;
  logic bus_sm_en_wr_p1;
  logic gpu_sm_en_wr_p1;
  logic en_p0;
  logic en_wr_p1;
  logic en_rd_p1;
  logic [31:0] writedata_p0;
  logic [ 2:0] addr_p0;
  
  // register_file
  gpu_ctrl_regfile #(
    .NUM_REGS(NUM_REGS)
  ) regf0 (
    .clk, .reset,
    .rd_en_p0_i     (1'h0), // todo: 1 or 0?
    .wr_en_p0_i     (en_p0),
    .addr_p0_i      (addr_p0),
    .writedata_p0_i (writedata_p0),

    .rd_en_p1_i     (en_rd_p1),
    .wr_en_p1_i     (en_wr_p1),
    .addr_p1_i      (i_wb_addr),
    .writedata_p1_i (i_wb_data),
    .readdata_p1_o  (o_wb_data),

    .writemask(regf_writemask),

    .regf_start,
    .input_mem_offset_addr_o,
    .output_mem_offset_addr_o,
    .intr_clr_gpu_done_o(irq_clr_gpu_done),
    .intr_stat_gpu_done_i(irq_gpu_done)
  );

  assign irq_gpu = irq_gpu_done; // this is the only irq for now

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

  // interrupt generation - gpu done
  intr_gen intr_gen0 (
    .clk, .reset,
    .event_i    (gpu_done),
    .irq_clr_i  (irq_clr_gpu_done),
    .irq_o      (irq_gpu_done)
  );

  // gpu working - need a signal that keeps track of whether the gpu is working or not
  // gpu is working if posedge of start_o is detected and ~ready_o
  // delayed start_o
  always_ff @(posedge clk) start_d <= reset ? '0 : start_o;

  // posedge detect
  always_ff @(posedge clk) begin
    if (reset)
      posedge_start_detected <= 0;
    else if (start_o && ~start_d) // start
      posedge_start_detected <= 1;
    else if (gpu_done) // done
      posedge_start_detected <= 0;
    else
      posedge_start_detected <= posedge_start_detected;
  end

  always_ff @(posedge clk) gpu_working <= reset ? '0 : posedge_start_detected && ~ready_i;

  assign gpu_done = posedge_start_detected & ready_i;

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


module gpu_ctrl_regfile #(
  parameter NUM_REGS = 5
)(
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

  // External control for write protection
  input  logic [31:0] writemask [NUM_REGS],

  // register bit fields
  output logic        regf_start,
  output logic [31:0] input_mem_offset_addr_o,
  output logic [31:0] output_mem_offset_addr_o,
  output logic        intr_clr_gpu_done_o,
  input  logic        intr_stat_gpu_done_i

);

  logic gpu_reset_req;

  // localparam NUM_REGS = 4;
  localparam logic [31:0] DEFAULT_WRITEMASK = 32'hFFFFFFFF; // Default full write access

  // Effective writemask: If not specified, default to 32'hFFFFFFFF
  logic [31:0] effective_writemask [NUM_REGS];

  generate
    genvar i;
    for (i = 0; i < NUM_REGS; i++) begin : gen_writemask
      assign effective_writemask[i] = (|writemask[i]) ? writemask[i] : DEFAULT_WRITEMASK;
    end
  endgenerate

  // Declare the register file
  logic [31:0] registers [NUM_REGS];

  assign regf_start          = registers[0][0];
  assign gpu_reset_req       = registers[0][1];
  assign input_mem_offset_addr_o   = registers[3];
  assign output_mem_offset_addr_o   = registers[4];
  assign intr_clr_gpu_done_o = registers[2][0];

  // Read operations for Port 1 and Port 2
  always_ff @( posedge clk ) begin
    if (reset) begin
      readdata_p0_o <= 32'd0;
      readdata_p1_o <= 32'd0;
    end else begin

      if (rd_en_p0_i) begin
        readdata_p0_o <= (addr_p0_i < NUM_REGS) ? registers[addr_p0_i] : '0;
      end else
        readdata_p0_o <= readdata_p0_o;

      if (rd_en_p1_i) begin
        readdata_p1_o <= (addr_p1_i < NUM_REGS) ? registers[addr_p1_i] : '0;
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
      registers[addr_p0_i] <= (registers[addr_p0_i] & ~effective_writemask[addr_p0_i]) | (writedata_p0_i & effective_writemask[addr_p0_i]);
    end

    if (wr_en_p1_i && (addr_p1_i < NUM_REGS)) begin
      registers[addr_p1_i] <= (registers[addr_p1_i] & ~effective_writemask[addr_p1_i]) | (writedata_p1_i & effective_writemask[addr_p1_i]);
    end

    // constant assignments
    registers[1][31:1] <= '0;
    registers[1][0]    <= intr_stat_gpu_done_i;

    // self clearing
    if (|registers[2]) registers[2] <= '0;

    end
  end

endmodule

// this module generates an interrupt (irq_o) based of of an external event (event_i)
// this event is captured by a rising edge of event_i (which can either be held or pulsed)
// if event_i is held and the irq is cleared, the module should not generate another irq! The state machine should only reset to idle if event_i is low
// if multiple pulses of event_i occur before the irq is cleared, then it should count as 1 event (for simplicity)
module intr_gen (
  input  logic clk, reset,
  input  logic event_i,   // signals occurrence of the event
  input  logic irq_clr_i, // requests that irq_o be deasserted if asserted (event ack)
  output logic irq_o      // primary irq line
);

  typedef enum logic [1:0] {
    IDLE,      // Waiting for an event
    PENDING,   // IRQ asserted, waiting for clear
    HOLD       // Waiting for event_i to go low after clearing
  } state_t;

  state_t state, next_state;
  logic event_d;  // Delayed event_i for edge detection

  // Edge detection
  always_ff @(posedge clk) begin
    if (reset)
      event_d <= 1'b0;
    else
      event_d <= event_i;
  end

  wire event_rise = event_i & ~event_d; // Detect rising edge of event_i

  // State transition logic
  always_ff @(posedge clk) begin
    if (reset)
      state <= IDLE;
    else
      state <= next_state;
  end

  // Next state logic
  always_comb begin
    case (state)
      IDLE: begin
        if (event_rise)
          next_state = PENDING;
        else
          next_state = IDLE;
      end
      PENDING: begin
        if (irq_clr_i)
          next_state = HOLD;
        else
          next_state = PENDING;
      end
      HOLD: begin
        if (!event_i)
          next_state = IDLE;
        else
          next_state = HOLD;
      end
      default: next_state = IDLE;
    endcase
  end

  // Output logic
  always_ff @(posedge clk) begin
    if (reset)
      irq_o <= 1'b0;
    else if (next_state == IDLE)
      irq_o <= 1'b0;
    else if (next_state == PENDING)
      irq_o <= 1'b1;
    else if (next_state == HOLD)
      irq_o <= 1'b0;
  end

endmodule
