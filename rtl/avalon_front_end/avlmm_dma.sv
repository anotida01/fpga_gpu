

module avlmm_dma_master (
  input  logic clk, reset,

  // Avalon MM Master port - read only
  input  logic [31:0] readdata,
  input  logic [ 0:0] waitrequest,
  output logic [31:0] address, // must be aligned to readdata
  output logic [ 0:0] read,
  output logic [ 3:0] byteenable,

  // resp signals to GPU
  input  logic [ 0:0] ready_i,
  output logic [ 0:0] valid_o,
  output logic [31:0] dma_out,

  // req signals from GPU
  output logic [ 0:0] ready_o,
  input  logic [ 0:0] valid_i,
  input  logic [31:0] address_i,

  // from GPU CTRL REG
  input  logic [31:0] mem_offset_addr_i

);


  typedef enum logic [1:0] { 
    RESET,
    IDLE,
    READ_REQ,
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
      dma_out       <= en_reg_dma_out   ? readdata  : dma_out;
    end
  end

  always_comb begin : output_logic

    // to gpu
    ready_o = 0;
    valid_o = 0;
    // dma_out = readdata;

    // to avl
    address = mem_offset_addr_i + address_i_reg;
    read = 0;
    byteenable = 0;

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

      READ_REQ : begin
        ready_o = 0;
        read = 1;
        byteenable = '1;

        if (~waitrequest) begin
          next_state = DONE;
          en_reg_dma_out = 1;
        end
        else
          next_state = READ_REQ;
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

