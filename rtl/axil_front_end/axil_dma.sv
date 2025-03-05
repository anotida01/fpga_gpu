

module axil_dma_master (
  input  logic clk, reset,

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

  // resp signals to GPU
  input  logic        ready_i,
  output logic        valid_o,
  output logic [31:0] dma_out,

  // req signals from GPU
  output logic        ready_o,
  input  logic        valid_i,
  input  logic [31:0] address_i,

  // from GPU CTRL REG
  input  logic [31:0] mem_offset_addr_i

);

  typedef enum logic [2:0] { 
    RESET,
    IDLE,
    WAIT_NO_STALL,
    READ_REQ,
    WAIT_ACK,
    DONE
   } state_e;

  state_e state, next_state;
  always_ff @( posedge clk ) begin : state_logic
    if (reset) state <= RESET;
    else state <= next_state;
  end

  logic en_reg_address_i;
  logic en_reg_dma_out;
  logic [31:0] address_i_reg;
  always_ff @( posedge clk ) begin : regs
    if (reset) begin 
      address_i_reg <= '0;
      dma_out <= '0;
    end
    else begin
      address_i_reg <= en_reg_address_i ? address_i : address_i_reg;
      dma_out       <= en_reg_dma_out   ? wb_data_i : dma_out;
    end
  end

  // todo: optimize so that we don't have to hit WAIT_NO_STALL each time
  always_comb begin : output_logic

    // to gpu
    ready_o = 0;
    valid_o = 0;

    // to wb
    wb_addr_o = mem_offset_addr_i + address_i_reg;
    wb_cyc_o = 0;
    wb_stb_o = 0;
    wb_we_o = 0;
    wb_data_o = 0;
    wb_sel_o = 0;

    // internal
    en_reg_address_i = 0;
    en_reg_dma_out = 0;
    next_state = state;
    
    case ({state})
      RESET :  begin
        ready_o = 0;
        next_state = IDLE;
      end

      IDLE : begin
        ready_o = 1;
        if (valid_i) begin
          next_state = READ_REQ;
          en_reg_address_i = 1;
        end
      end

      WAIT_NO_STALL : begin
        ready_o = 0;
        if (~wb_stall_i)
          next_state = READ_REQ;
        else
          next_state = WAIT_NO_STALL;
      end

      READ_REQ : begin
        ready_o = 0; // tell gpu not ready
        
        // signal read to bus
        wb_cyc_o = 1;
        wb_stb_o = 1;
        wb_we_o = 0;

        // danger! assumes that ack will not come back in the same cycle!!
        if (wb_stall_i)
          next_state = READ_REQ;
        else 
          next_state = WAIT_ACK;
      end 

      WAIT_ACK : begin

      wb_cyc_o = 1;

        if (wb_ack_i) begin // then latch the data
          en_reg_dma_out = 1;
          next_state = DONE;
        end else
          next_state = WAIT_ACK;

      end

      DONE : begin
        valid_o = 1;
        if (ready_i) next_state = IDLE;
        else         next_state = DONE;
      end

      default: next_state = RESET;
    endcase

  end


endmodule

