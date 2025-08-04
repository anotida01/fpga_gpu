module axil_rop_backend #(
  parameter INPUT_FIFO_DEPTH = 32,
  parameter OUTPUT_FIFO_DEPTH = 32,
  parameter ROP_X_WIDTH = 32,
  parameter ROP_Y_WIDTH = 32,
  parameter ROP_C_WIDTH = 32
)(
  input  logic             clk,
  input  logic             reset,

  // to axi bus
  output logic             rop_axi_awvalid_o,// AW
  input  logic             rop_axi_awready_i,
  output logic [31:0]      rop_axi_awaddr_o,
  output logic [ 2:0]      rop_axi_awprot_o,
  output logic             rop_axi_wvalid_o , // W
  input  logic             rop_axi_wready_i,
  output logic [31:0]      rop_axi_wdata_o,
  output logic [32/8-1:0]  rop_axi_wstrb_o,
  input  logic             rop_axi_bvalid_i, // B
  input  logic [1:0]       rop_axi_bresp_i,
  output logic             rop_axi_bready_o,
  output logic             rop_axi_arvalid_o,// AR
  input  logic             rop_axi_arready_i,
  output logic [31:0]      rop_axi_araddr_o,
  output logic [ 2:0]      rop_axi_arprot_o,
  input  logic             rop_axi_rvalid_i, // R
  output logic             rop_axi_rready_o,
  input  logic [31:0]      rop_axi_rdata_i,
  input  logic [ 1:0]      rop_axi_rresp_i,

  // to/from ROP
  input  logic        [ROP_X_WIDTH-1:0] x_i,
  input  logic        [ROP_Y_WIDTH-1:0] y_i,
  input  logic signed [ROP_C_WIDTH-1:0] c_i,

  // ready/valid
  input  logic valid_i,
  output logic ready_o,

  // from front end
  input  logic [31:0] output_mem_offset_addr_i
);
  // this is the overall flow of this module
  // input FIFO -> optional upscaler -> optional upscaler fifo -> WB Bus SM -> wb2axil adaptor -> BUS

  localparam FIFO_DATA_WIDTH = ROP_X_WIDTH + ROP_Y_WIDTH + ROP_C_WIDTH;

  // input fifo
  logic                       reset_n;
  logic                       infifo_wclk;
  logic                       infifo_wrst_n;
  logic                       infifo_winc;
  logic [FIFO_DATA_WIDTH-1:0] infifo_wdata;
  logic                       infifo_wfull;
  logic                       infifo_awfull;
  logic                       infifo_rclk;
  logic                       infifo_rrst_n;
  logic                       infifo_rinc;
  logic [FIFO_DATA_WIDTH-1:0] infifo_rdata;
  logic                       infifo_rempty;
  logic                       infifo_arempty;

  // output fifo
  logic                       outfifo_wclk;
  logic                       outfifo_wrst_n;
  logic                       outfifo_winc;
  logic [FIFO_DATA_WIDTH-1:0] outfifo_wdata;
  logic                       outfifo_wfull;
  logic                       outfifo_awfull;
  logic                       outfifo_rclk;
  logic                       outfifo_rrst_n;
  logic                       outfifo_rinc;
  logic [FIFO_DATA_WIDTH-1:0] outfifo_rdata;
  logic                       outfifo_rempty;
  logic                       outfifo_arempty;

  // wb master
  logic [31:0]      wr_mstr_wb_addr;
  logic             wr_mstr_wb_cyc;
  logic             wr_mstr_wb_stb;
  logic             wr_mstr_wb_we;
  logic [31:0]      wr_mstr_wb_data_i;
  logic [31:0]      wr_mstr_wb_data_o;
  logic [32/8-1:0]  wr_mstr_wb_sel;
  logic             wr_mstr_wb_ack;
  logic             wr_mstr_wb_err;
  logic             wr_mstr_wb_stall;
  
  logic        [ROP_X_WIDTH-1:0] rop_normalize_x;
  logic        [ROP_Y_WIDTH-1:0] rop_normalize_y;
  logic signed [ROP_C_WIDTH-1:0] rop_normalize_c;
  logic                          rop_normalize_valid;


  assign reset_n = ~reset;
  assign infifo_wdata = {rop_normalize_x, rop_normalize_y, rop_normalize_c};
  assign infifo_wclk = clk;
  assign infifo_rclk = clk;
  assign infifo_wrst_n = reset_n;
  assign infifo_rrst_n = reset_n;
  assign infifo_winc = rop_normalize_valid;

  assign outfifo_wclk = clk;
  assign outfifo_rclk = clk;
  assign outfifo_wrst_n = reset_n;
  assign outfifo_rrst_n = reset_n;

  assign ready_o = ~infifo_wfull;

  rop_normalize rop_normalize_inst (
    .x_i      (x_i),
    .y_i      (y_i),
    .c_i      (c_i),
    .valid_i  (valid_i),
    .y_o      (rop_normalize_y),
    .x_o      (rop_normalize_x),
    .c_o      (rop_normalize_c),
    .valid_o  (rop_normalize_valid)
  );

  async_fifo #(
    .DSIZE(FIFO_DATA_WIDTH),
    .ASIZE(INPUT_FIFO_DEPTH),
    .FALLTHROUGH("FALSE")
  ) input_fifo (
    .wclk     (infifo_wclk),
    .wrst_n   (infifo_wrst_n),
    .winc     (infifo_winc),
    .wdata    (infifo_wdata),
    .wfull    (infifo_wfull),
    .awfull   (infifo_awfull),
    .rclk     (infifo_rclk),
    .rrst_n   (infifo_rrst_n),
    .rinc     (infifo_rinc),
    .rdata    (infifo_rdata),
    .rempty   (infifo_rempty),
    .arempty  (infifo_arempty)
  );

  // pixel_upsample  #(
  //   .ROP_X_WIDTH(ROP_X_WIDTH),
  //   .ROP_Y_WIDTH(ROP_Y_WIDTH),
  //   .ROP_C_WIDTH(ROP_C_WIDTH)
  // ) pixel_upsample_inst (
  //   .clk(clk),
  //   .reset(reset),

  //   // infifo read control signals
  //   .infifo_rinc_o      (infifo_rinc),
  //   .infifo_rdata_i     (infifo_rdata),
  //   .infifo_rempty_i    (infifo_rempty),
  //   .infifo_arempty_i   (infifo_arempty),

  //   // outfifo write control signals
  //   .outfifo_winc_o     (outfifo_winc),
  //   .outfifo_wdata_o    (outfifo_wdata),
  //   .outfifo_wfull_i    (outfifo_wfull),
  //   .outfifo_awfull_i   (outfifo_awfull)
  // );

  // async_fifo #(
  //   .DSIZE(FIFO_DATA_WIDTH),
  //   .ASIZE(OUTPUT_FIFO_DEPTH),
  //   .FALLTHROUGH("FALSE")
  // ) output_fifo (
  //   .wclk     (outfifo_wclk),
  //   .wrst_n   (outfifo_wrst_n),
  //   .winc     (outfifo_winc),
  //   .wdata    (outfifo_wdata),
  //   .wfull    (outfifo_wfull),
  //   .awfull   (outfifo_awfull),
  //   .rclk     (outfifo_rclk),
  //   .rrst_n   (outfifo_rrst_n),
  //   .rinc     (outfifo_rinc),
  //   .rdata    (outfifo_rdata),
  //   .rempty   (outfifo_rempty),
  //   .arempty  (outfifo_arempty)
  // );

  wb_write_master #(
    .ROP_X_WIDTH(ROP_X_WIDTH),
    .ROP_Y_WIDTH(ROP_Y_WIDTH),
    .ROP_C_WIDTH(ROP_C_WIDTH)
  ) wb_write_master_inst (
    .clk                (clk),
    .reset              (reset),

    // WB Master Port
    .wb_addr_o          (wr_mstr_wb_addr),
    .wb_cyc_o           (wr_mstr_wb_cyc),
    .wb_stb_o           (wr_mstr_wb_stb),
    .wb_we_o            (wr_mstr_wb_we),
    .wb_data_o          (wr_mstr_wb_data_o),
    .wb_data_i          (wr_mstr_wb_data_i),
    .wb_sel_o           (wr_mstr_wb_sel),
    .wb_ack_i           (wr_mstr_wb_ack),
    .wb_err_i           (wr_mstr_wb_err),
    .wb_stall_i         (wr_mstr_wb_stall),

    // outfifo read control signals
    // todo: remember to change all reference of outfifo to infifo?
    .outfifo_rinc_o     (infifo_rinc),
    .outfifo_rdata_i    (infifo_rdata),
    .outfifo_rempty_i   (infifo_rempty),
    .outfifo_arempty_i  (infifo_arempty),

    // from GPU CTRL REG
    .mem_offset_addr_i  (output_mem_offset_addr_i)
  );

  logic [31:0] rop_axi_awaddr;
  logic [31:0] rop_axi_araddr;

  wbm2axilite #(
    .C_AXI_ADDR_WIDTH(32)
  ) mstr_wbm2axil_inst (
    .i_clk          (clk),
    .i_reset        (reset),
    .i_wb_addr      (wr_mstr_wb_addr),
    .i_wb_cyc       (wr_mstr_wb_cyc),
    .i_wb_stb       (wr_mstr_wb_stb),
    .i_wb_we        (wr_mstr_wb_we),
    .i_wb_data      (wr_mstr_wb_data_o),
    .i_wb_sel       (wr_mstr_wb_sel),
    .o_wb_data      (wr_mstr_wb_data_i),
    .o_wb_ack       (wr_mstr_wb_ack),
    .o_wb_err       (wr_mstr_wb_err),
    .o_wb_stall     (wr_mstr_wb_stall),

    .o_axi_awvalid  (rop_axi_awvalid_o), 
    .i_axi_awready  (rop_axi_awready_i),
    .o_axi_awaddr   (rop_axi_awaddr),
    .o_axi_awprot   (rop_axi_awprot_o),
    .o_axi_wvalid   (rop_axi_wvalid_o),
    .i_axi_wready   (rop_axi_wready_i),
    .o_axi_wdata    (rop_axi_wdata_o),
    .o_axi_wstrb    (rop_axi_wstrb_o),
    .i_axi_bvalid   (rop_axi_bvalid_i),
    .i_axi_bresp    (rop_axi_bresp_i),
    .o_axi_bready   (rop_axi_bready_o),
    .o_axi_arvalid  (rop_axi_arvalid_o),
    .i_axi_arready  (rop_axi_arready_i),
    .o_axi_araddr   (rop_axi_araddr),
    .o_axi_arprot   (rop_axi_arprot_o),
    .i_axi_rvalid   (rop_axi_rvalid_i),
    .o_axi_rready   (rop_axi_rready_o),
    .i_axi_rdata    (rop_axi_rdata_i),
    .i_axi_rresp    (rop_axi_rresp_i)
  );

  assign rop_axi_awaddr_o = rop_axi_awaddr + output_mem_offset_addr_i;
  assign rop_axi_araddr_o = rop_axi_araddr + output_mem_offset_addr_i;

endmodule

module rop_normalize (
  input clk, reset, 
  input [31:0] x_i, y_i,
  input signed [31:0] c_i,

  output [8:0] x_o, 
  output [7:0] y_o,
  output [14:0] c_o,

  input valid_i,
  output logic ready_o, valid_o
);

  wire signed [63:0] c = 64'h07C000;
  wire signed [63:0] c_inter, c_shift;

  assign c_inter = c_i * c;
  assign c_shift = c_inter >>> 28;
  wire [4:0] cc = c_shift[4:0];
  assign c_o = (c_i < 32'sd0) ? 15'd0 : {cc, cc, cc};

  localparam HALF = 32'd1 << 13;
  wire [31:0] x = (x_i + HALF) >>> 14;
  wire [31:0] y = (y_i + HALF) >>> 14;
  assign x_o = x;
  assign y_o = y;

  assign ready_o = 1;
  assign valid_o = valid_i;
endmodule


module pixel_upsample #(
  parameter ROP_X_WIDTH = 32,
  parameter ROP_Y_WIDTH = 32,
  parameter ROP_C_WIDTH = 32,
  parameter FIFO_DATA_WIDTH = ROP_X_WIDTH + ROP_Y_WIDTH + ROP_C_WIDTH
)(
  input  logic clk,
  input  logic reset,

  // infifo read control signals
  output logic                        infifo_rinc_o,
  input  logic [FIFO_DATA_WIDTH-1:0]  infifo_rdata_i,
  input  logic                        infifo_rempty_i,
  input  logic                        infifo_arempty_i,

  // outfifo write control signals
  output logic                        outfifo_winc_o,
  output logic [FIFO_DATA_WIDTH-1:0]  outfifo_wdata_o,
  input  logic                        outfifo_wfull_i,
  input  logic                        outfifo_awfull_i
);

  // input regs
  logic                       en_i_regs;
  logic [FIFO_DATA_WIDTH-1:0] infifo_rdata_r;
  logic [ROP_X_WIDTH-1:0]     x_r;
  logic [ROP_Y_WIDTH-1:0]     y_r;
  logic [ROP_C_WIDTH-1:0]     c_r;

  always_ff @( clk ) begin : i_regs
    if (reset) begin
      infifo_rdata_r <= '0;
    end else if (en_i_regs) begin
      infifo_rdata_r <= infifo_rdata_i;
    end else begin
      infifo_rdata_r <= infifo_rdata_r;
    end
  end

  assign {x_r, y_r, c_r} = infifo_rdata_r; // is this legal systemverilog?

  // control state machine here
  // default state is IDLE (states should be made using an enum)
  // when infifo is no longer empty, initiate a read to the rfifo using infifo_rinc
  // in the next cycle, enable the input register to capture the values from the fifo
  // the upsampling works by duplicating c_r at positions x_r+1, and y_r+1
  // write to the output fifo all the pixel data (color c_r at [x, y], [x+1, y], [x, y+1], [x+1, y+1])
  // the format for the wdata_o signal is the same as the rdata_i signal (i.e. {x, y, c} packed into single signal)

  typedef enum logic [2:0] {
    IDLE,
    READ_FIFO,
    WAIT_DATA,
    WRITE_P0,
    WRITE_P1,
    WRITE_P2,
    WRITE_P3
  } state_t;

  state_t state, next_state;

  // control signals
  assign infifo_rinc_o = (state == READ_FIFO);
  assign en_i_regs     = (state == WAIT_DATA);

  // Sequential state register
  always_ff @(posedge clk or posedge reset) begin
    if (reset)
      state <= IDLE;
    else
      state <= next_state;
  end

  // Combined output and next-state logic
  always_comb begin
    // defaults
    next_state        = state;
    outfifo_winc_o    = 0;
    outfifo_wdata_o   = '0;

    case (state)
      IDLE: begin
        if (!infifo_rempty_i)
          next_state = READ_FIFO;
      end

      READ_FIFO: begin
        next_state = WAIT_DATA;
      end

      WAIT_DATA: begin
        next_state = WRITE_P0;
      end

      WRITE_P0: begin
        if (!outfifo_awfull_i) begin
          outfifo_winc_o  = 1;
          outfifo_wdata_o = {x_r, y_r, c_r};
          next_state      = WRITE_P1;
        end
      end

      WRITE_P1: begin
        if (!outfifo_awfull_i) begin
          outfifo_winc_o  = 1;
          outfifo_wdata_o = {x_r + 1, y_r, c_r};
          next_state      = WRITE_P2;
        end
      end

      WRITE_P2: begin
        if (!outfifo_awfull_i) begin
          outfifo_winc_o  = 1;
          outfifo_wdata_o = {x_r, y_r + 1, c_r};
          next_state      = WRITE_P3;
        end
      end

      WRITE_P3: begin
        if (!outfifo_awfull_i) begin
          outfifo_winc_o  = 1;
          outfifo_wdata_o = {x_r + 1, y_r + 1, c_r};
          next_state      = IDLE;
        end
      end

      default: next_state = IDLE;
    endcase
  end
endmodule


module wb_write_master #(
  parameter ROP_X_WIDTH = 32,
  parameter ROP_Y_WIDTH = 32,
  parameter ROP_C_WIDTH = 32,
  parameter FIFO_DATA_WIDTH = ROP_X_WIDTH + ROP_Y_WIDTH + ROP_C_WIDTH
)(
  input  logic clk,
  input  logic reset,

  // WB Master Port
  output logic [31:0]     wb_addr_o,
  output logic            wb_cyc_o,
  output logic            wb_stb_o,
  output logic            wb_we_o,
  output logic [31:0]     wb_data_o,
  input  logic [31:0]     wb_data_i,
  output logic [32/8-1:0] wb_sel_o,
  input  logic            wb_ack_i,
  input  logic            wb_err_i,
  input  logic            wb_stall_i,

  // outfifo read control signals
  output logic                        outfifo_rinc_o,
  input  logic [FIFO_DATA_WIDTH-1:0]  outfifo_rdata_i,
  input  logic                        outfifo_rempty_i,
  input  logic                        outfifo_arempty_i,

  // from GPU CTRL REG
  input  logic [31:0] mem_offset_addr_i
);

  localparam BYTES_PER_WORD = 2; // using 16bit color mode for now

  
  logic                       en_i_regs;
  logic [FIFO_DATA_WIDTH-1:0] outfifo_rdata_r;
  logic [ROP_X_WIDTH-1:0]     x_r;
  logic [ROP_Y_WIDTH-1:0]     y_r;
  logic [ROP_C_WIDTH-1:0]     c_r;
  logic                       x_lsb;
  logic [31:0] target_byte_address;
  logic [31:0] target_word_address;
  logic [15:0] colour_data_16b;

  // input regs
  always_ff @( posedge clk ) begin : i_regs
    if (reset) begin
      outfifo_rdata_r <= '0;
    end else if (en_i_regs) begin
      outfifo_rdata_r <= outfifo_rdata_i;
    end else begin
      outfifo_rdata_r <= outfifo_rdata_r;
    end
  end

  assign {x_r, y_r, c_r} = outfifo_rdata_r;
  assign x_lsb = x_r[0];
  
  // DE1 SoC Computer Sys VGA controller colour format
  // MSB                             LSB
  // {Red (5 bits), Green (6 bits), Blue (5bits)}
  // assign colour_data_16b = {c_r[4:0], 1'b0, c_r[4:0], c_r[4:0]};
  assign colour_data_16b = {c_r[4:0], c_r[4:0], 1'b0, c_r[4:0]};

  // assign colour_data_16b = {5'b11111, 6'b0, 5'b0};

  assign target_byte_address = {'0, y_r[7:0], x_r[8:0], 1'b0};
  assign target_word_address = target_byte_address >> 2; // always 32b aligned

  assign wb_addr_o = target_word_address;
  assign wb_data_o = x_lsb ? {colour_data_16b, 16'b0} : {16'b0, colour_data_16b};

  typedef enum logic [2:0] { 
    RESET,
    IDLE,
    READ_FIFO,
    WAIT_DATA,
    WAIT_NO_STALL,
    WRITE_REQ,
    WAIT_ACK
    // DONE
   } state_e;

  state_e state, next_state;
  always_ff @( posedge clk ) begin : state_logic
    if (reset) state <= RESET;
    else state <= next_state;
  end

  always_comb begin : output_logic

    // to wb
    // wb_addr_o = mem_offset_addr_i + address_i_reg;
    wb_cyc_o = 0;
    wb_stb_o = 0;
    wb_we_o = 0;
    // wb_data_o = 0;
    wb_sel_o = 0;

    // to fifo
    outfifo_rinc_o = 0;

    // internal
    en_i_regs = 0;
    next_state = state;

    case ({state})
      RESET :  begin
        next_state = IDLE;
      end

      IDLE : begin
        if (~outfifo_rempty_i) begin
          next_state = READ_FIFO;
        end
      end

      READ_FIFO : begin
        outfifo_rinc_o = 1;
        next_state = WAIT_DATA;
      end

      WAIT_DATA : begin
        en_i_regs = 1;
        next_state = WRITE_REQ;
      end

      WAIT_NO_STALL : begin
        if (~wb_stall_i)
          next_state = WRITE_REQ;
        else
          next_state = WAIT_NO_STALL;
      end

      WRITE_REQ : begin
        // signal read to bus
        wb_cyc_o = 1;
        wb_stb_o = 1;
        wb_we_o = 1;
        
        if (x_lsb) // data is on highest 16bits of data bus
          wb_sel_o = 'hC;
        else // data is on lower 16bits
          wb_sel_o = 'h3;

        // danger! assumes that ack will not come back in the same cycle!!
        if (wb_stall_i)
          next_state = WRITE_REQ;
        else 
          next_state = WAIT_ACK;
      end 

      WAIT_ACK : begin

      wb_cyc_o = 1;
      if (x_lsb) // data is on highest 16bits of data bus
        wb_sel_o = 'hC;
      else // data is on lower 16bits
        wb_sel_o = 'h3;

        if (wb_ack_i) begin // then latch the data
          next_state = IDLE;
        end else
          next_state = WAIT_ACK;

      end

      // DONE : begin
      //   valid_o = 1;
      //   if (ready_i) next_state = IDLE;
      //   else         next_state = DONE;
      // end

      default: next_state = RESET;
    endcase

  end
endmodule
