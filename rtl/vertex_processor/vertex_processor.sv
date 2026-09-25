`timescale 1ps/1ps

module vertex_processor (
  input  logic [ 0:0] clk, reset, start_i,

  input  logic [31:0] dma_data_i,
  input  logic [ 0:0] dma_ready_i,
  input  logic [ 0:0] dma_valid_i,
  output logic [ 0:0] gpu_valid_o,
  output logic [31:0] gpu_address_o,
  output logic [ 0:0] gpu_done_o,
  output logic [ 0:0] gpu_ready_o,

  // to vertex FIFO
  output logic [107:0] vertex_xyzw,
  output logic [  0:0] v_fifo_wrreq,
  input  logic [  0:0] v_fifo_full,

  // to vertex normal FIFO
  output logic [26:0] shade_vn_o,
  output logic [ 0:0] vn_fifo_wrreq,
  input  logic [ 0:0] vn_fifo_full

);

  logic xform_valid_i;
  logic shade_valid_i;
  logic shade_valid_o;
  logic shade_ready;

  logic [31:0] dma_data;
  always_ff @( posedge clk ) begin : i_regs
    dma_data <= reset ? '0 : dma_data_i;
  end

  // vertex normal shader

  assign vn_fifo_wrreq = shade_valid_o;
  vn_shade vn_shade_inst (
    .valid_i(shade_valid_i),
    .ready_i(~vn_fifo_full),
    .vn     (dma_data[26:0]),
    .vn_o   (shade_vn_o),
    .valid_o(shade_valid_o),
    .ready_o(shade_ready),
    .*
  );

  // vertex transformation
  wire xform_ready;
  v_xform v_xform_inst (
    .valid_i(xform_valid_i && xform_ready),
    .ready_o(xform_ready),
    .data(dma_data[26:0]),
    .ready_i(~v_fifo_full),
    .valid_o(v_fifo_wrreq),
    .*
  );

  // state machine that requests all the data
  // passes vertices to matrix-vector unit
  // passes normals to shading unit

  vertex_processor_sm_v2 sm0 (
    .clk,
    .reset,
    .start_i,
    .xform_ready,
    .shade_ready,
    .dma_data_i,
    .dma_ready_i,
    .dma_valid_i,
    .gpu_valid_o,
    .gpu_ready_o,
    .gpu_done_o,
    .gpu_address_o,
    .xform_valid_i,
    .shade_valid_i
  );

endmodule

module vertex_processor_sm (
  input  logic [ 0:0] clk, reset, 
  input  logic [ 0:0] start_i,
  input  logic [ 0:0] xform_ready, 
  input  logic [ 0:0] shade_ready,

  input  logic [31:0] dma_data_i,
  input  logic [ 0:0] dma_ready_i,
  input  logic [ 0:0] dma_valid_i,

  output logic [ 0:0] gpu_valid_o,
  output logic [ 0:0] gpu_done_o,
  output logic [ 0:0] gpu_ready_o,

  output logic [31:0] gpu_address_o,
  output logic [ 0:0] xform_valid_i,
  output logic [ 0:0] shade_valid_i

);

  // general purpose timer triggered by clk
  logic [31:0] timer_value;
  logic [31:0] timer_preload;
  logic [ 0:0] timer_done;
  logic [ 0:0] timer_en;
  logic [ 0:0] timer_clk_en;
  timer_clk #(.WIDTH(32)) time0 (
    .clk,
    .reset,
    .clk_en       (timer_clk_en),
    .preload      (timer_en),
    .preload_val  (timer_preload),
    .value        (timer_value),
    .timer_done
  );

  // general purpose timer triggered by en
  // used to track vertex vs. normal
  logic [7:0] counter_value;
  logic [7:0] counter_preload_val;
  logic [0:0] counter_done;
  logic [0:0] counter_en;
  logic [0:0]counter_preload;
  timer_en #(.WIDTH(8), .UP(0)) time1 (
    .clk, 
    .reset,
    .preload      (counter_preload),
    .preload_val  (counter_preload_val),
    .en           (counter_en),
    .value        (counter_value),
    .done         (counter_done)
  );

  // abstract state 
  typedef enum logic [3:0] {
    RESET,
    IDLE,
    FETCH_MATRIX,
    FETCH_LIGHT,
    FETCH_NUM_VRTX,
    SET_NUM_VRTX,
    FETCH_VERTEX,
    PREFETCH_VERTEX,
    FETCH_NORMAL,
    BACKTRACK,
    WAIT_MEMORY,
    XFORM_BUSY,
    XXX
  } state_e;

  // TODO (sept 17 2023) we've made yet another assumption that the shader and xform odules will
  // always be ready (an ok assumption for now). 
  // We may need to yet again modify SM to support back-pressure throughout the entire system

  state_e state, next_state, prev_state;
  always_ff @( posedge clk ) begin : state_logic
    if (reset) state <= RESET;
    else state <= next_state;
    prev_state <= state;
  end

  always_comb begin : next_state_logic

    next_state = RESET;

    case ({state})
      RESET : next_state = IDLE;

      IDLE : begin
        next_state = start_i ? FETCH_MATRIX : state;
      end

      FETCH_MATRIX : begin
        if (timer_done) next_state = FETCH_LIGHT;
        else next_state = state;
      end

      FETCH_LIGHT : begin
        if (timer_done) next_state = FETCH_NUM_VRTX;
        else next_state = state;
      end

      FETCH_NUM_VRTX : begin
        next_state = SET_NUM_VRTX;
      end

      SET_NUM_VRTX : begin
        next_state = FETCH_VERTEX;
      end

      FETCH_VERTEX : begin
        if (~xform_ready) next_state = BACKTRACK;
        // else if (timer_done) next_state = RESET;
        else if (counter_done) next_state = FETCH_NORMAL;
        else next_state = state;
      end

      FETCH_NORMAL : begin
        // if (~shade_ready) next_state = BACKTRACK;
        if (timer_done) next_state = IDLE;
        else if (counter_done) next_state = FETCH_VERTEX;
        else next_state = state;
      end

      BACKTRACK : begin
        next_state = XFORM_BUSY;
      end

      XFORM_BUSY : begin
        if (xform_ready) next_state = PREFETCH_VERTEX;
        else next_state = state;
      end

      PREFETCH_VERTEX : begin
        next_state = FETCH_VERTEX;
      end

      default : next_state = XXX;
    endcase

  end

  always_ff @( posedge clk ) begin : output_logic
    // default values
    gpu_valid_o <= 0;
    gpu_done_o <= 0;
    gpu_ready_o  <= 1'b0;

    timer_en <= 0;
    timer_preload <= 8'd0;
    timer_clk_en <= 1'd0;

    gpu_address_o <= gpu_address_o;
    xform_valid_i <= 0;
    shade_valid_i <= 0;

    counter_preload <= 0;
    counter_preload_val <= 0;
    counter_en <= 0;

    case ({next_state})

      IDLE : begin
        gpu_done_o <= 1;
      end

      FETCH_MATRIX :  begin
        
        gpu_ready_o <= 1'd1;

        if (timer_done) begin // current_state = IDLE - reset counter
          timer_en <= 1;
          timer_preload <= 8'd15; // 16 values for composite 4x4 matrix
          // gpu_valid_o <= 0;
        end else begin // current state is fetch matrix

          // if 

          gpu_valid_o <= 1;
          gpu_address_o <= gpu_address_o + 'd1;
          xform_valid_i <= 1'd1;
        end

      end

      FETCH_LIGHT : begin

        if (timer_done) begin
          timer_en <= 1;
          timer_preload <= 8'd1;
        end

        gpu_valid_o <= 1;
        gpu_address_o <= gpu_address_o + 'd1;
        shade_valid_i <= 1;
      end

      FETCH_NUM_VRTX : begin

        gpu_valid_o <= 1;
        gpu_address_o <= gpu_address_o + 'd1;
        // num_vrtx_valid <= 1;
        
      end

      SET_NUM_VRTX : begin
        timer_en <= 1;
        timer_preload <= dma_data_i - 1;

        counter_preload_val <= 8'd3;
        counter_preload <= 1'd1;
      end

      FETCH_VERTEX : begin

        gpu_valid_o <= 1;
        gpu_address_o <= gpu_address_o + 'd1;
        xform_valid_i <= 1;
        counter_en <= 1;

        if (counter_done) begin
          counter_preload_val <= 8'd2;
          counter_preload <= 1'd1;
        end

      end

      FETCH_NORMAL : begin

        if (counter_done) begin
          counter_preload_val <= 8'd1;
          counter_preload <= 1'd1;
        end
        
        gpu_valid_o <= 1;
        gpu_address_o <= gpu_address_o + 'd1;
        shade_valid_i <= 1;
        counter_en <= 1;

      end

      BACKTRACK : begin
        gpu_address_o <= gpu_address_o - 'd2;
        timer_preload <= timer_value + 1;
        timer_en <= 1;
        counter_preload_val <= counter_preload_val + 8'd1;
        counter_preload <= 1;
      end

      XFORM_BUSY : begin
        gpu_address_o <= gpu_address_o;
        timer_clk_en <= 0;
      end

      PREFETCH_VERTEX : begin
        gpu_address_o <= gpu_address_o + 'd1;
        // counter_en <= 1;
        gpu_valid_o <= 1;
      end

      // default: 
    endcase

    // reset override
    if (reset)  begin
      gpu_address_o <= 'd0;
      gpu_done_o <= 0;
      // gpu_valid_o <= 0;
      // timer_en <= 0;
      // timer_preload <= 8'd0;
      xform_valid_i <= 0;
      shade_valid_i <= 0;
      // num_vrtx_valid <= 0;
    end

  end

endmodule

module vertex_processor_sm_v2 (
  input  logic [ 0:0] clk, reset, 
  input  logic [ 0:0] start_i,
  input  logic [ 0:0] xform_ready, 
  input  logic [ 0:0] shade_ready,

  input  logic [31:0] dma_data_i,
  input  logic [ 0:0] dma_ready_i,
  input  logic [ 0:0] dma_valid_i,

  output logic [ 0:0] gpu_valid_o,
  output logic [ 0:0] gpu_done_o,
  output logic [ 0:0] gpu_ready_o,

  output logic [31:0] gpu_address_o,
  output logic [ 0:0] xform_valid_i,
  output logic [ 0:0] shade_valid_i

);


  // general purpose timer triggered by clk
  logic [31:0] timer_value;
  logic [31:0] timer_preload;
  logic [ 0:0] timer_done;
  logic [ 0:0] timer_en;
  logic [ 0:0] timer_clk_en;
  timer_clk #(.WIDTH(32)) time0 (
    .clk,
    .reset,
    .clk_en       (timer_clk_en),
    .preload      (timer_en),
    .preload_val  (timer_preload),
    .value        (timer_value),
    .timer_done
  );

  // general purpose timer triggered by en
  // used to track vertex vs. normal
  logic [7:0] counter_value;
  logic [7:0] counter_preload_val;
  logic [0:0] counter_done;
  logic [0:0] counter_en;
  logic [0:0] counter_preload;
  timer_en #(.WIDTH(8), .UP(0)) time1 (
    .clk, 
    .reset,
    .preload      (counter_preload),
    .preload_val  (counter_preload_val),
    .en           (counter_en),
    .value        (counter_value),
    .done         (counter_done)
  );

  // abstract state 
  typedef enum logic [3:0] {
    RESET,
    IDLE,
    FETCH_MATRIX,
    FETCH_LIGHT,
    FETCH_NUM_VRTX,
    FETCH_VERTEX,
    FETCH_NORMAL,
    WAIT_DMA,
    XXX
  } state_e;

  state_e state, next_state, prev_state, return_state;
  always_ff @( posedge clk ) begin : state_logic
    if (reset) begin 
      state <= RESET;
      prev_state <= RESET;
      return_state <= RESET;
    end
    else begin 
      state <= next_state;
      prev_state <= state;

      // WAIT_DMA return target: capture the state being left on the edge
      // that enters WAIT_DMA. (The previous scheme — "on a detected state
      // change, return_state <= prev_state" — sampled prev_state one edge
      // too early, so a DMA response arriving within the first WAIT_DMA
      // cycle was returned to the state from *before* the fetch state
      // (IDLE, or RESET for the first word) and the frame was silently
      // aborted with no gpu_ready_o.
      if (next_state == WAIT_DMA && state != WAIT_DMA)
        return_state <= state;
    end
  end

  // tells the FETCH_* states whether data has been fetched
  logic data_has_been_fetched;
  logic en_data_has_been_fetched;
  always_ff @( posedge clk ) begin
    if (reset) 
      data_has_been_fetched <= 0;
    else if (en_data_has_been_fetched)
      data_has_been_fetched <= ~data_has_been_fetched;
    else
      data_has_been_fetched <= data_has_been_fetched;
  end

  logic gpu_address_reset;
  logic en_gpu_address_reg;
  // logic en_gpu_address_inc_reg;
  // logic [31:0] gpu_address_inc;
  always_ff @( posedge clk ) begin : gpu_address_reg
    
    if (en_gpu_address_reg)
      gpu_address_o <= gpu_address_o + 32'd1; // todo: this value is dependant on the type of front end in use!
    else
      gpu_address_o <= gpu_address_o;

    // if (en_gpu_address_inc_reg)
      
    if (reset | gpu_address_reset) begin
      gpu_address_o <= 32'd0;
      // gpu_address_inc <= 32'd0;
    end 
  end

  always_comb begin : sm_logic
    // default values
    gpu_valid_o = 0;
    gpu_done_o = 0;
    gpu_ready_o = 0;

    timer_en = 0;
    timer_preload = 8'd0;
    timer_clk_en = 1'd0;

    // gpu_address_o = gpu_address_o;
    gpu_address_reset = 0;
    en_gpu_address_reg = 0;
    en_data_has_been_fetched = 0;
    xform_valid_i = 0;
    shade_valid_i = 0;

    counter_preload = 0;
    counter_preload_val = 0;
    counter_en = 0;

    next_state = state;

    case ({state})

      RESET : begin
        next_state = IDLE;
      end

      IDLE : begin
        gpu_done_o = 1; 
        if (start_i) begin
          next_state = FETCH_MATRIX;
          timer_en = 1;
          timer_preload = 8'd15; // 16 values for composite 4x4 matrix
          gpu_address_reset = 1;
        end
        else
          next_state = state;
      end

      FETCH_MATRIX : begin
        if (data_has_been_fetched) begin

          if (xform_ready) begin
            xform_valid_i = 1; // might have to move this outside the if for true ready valid
            en_gpu_address_reg = 1;
            en_data_has_been_fetched = 1; // set to 0
            timer_clk_en = 1;
            gpu_ready_o = 1;

            if (timer_done) begin // move to next state
              next_state = FETCH_LIGHT;
              timer_en = 1;
              timer_preload = 8'd2; // not sure why preload is 1
            end else
              next_state = state;
          end else
            next_state = state;

        end else if (dma_ready_i) begin // data has not been fetched
          gpu_valid_o = 1; // req the address
          next_state = WAIT_DMA; // wait for data
        end
      
      end

      FETCH_LIGHT : begin
        if (data_has_been_fetched) begin

          if (shade_ready) begin
            shade_valid_i = 1; // might have to move this outside the if for true ready valid
            en_gpu_address_reg = 1;
            en_data_has_been_fetched = 1; // set to 0
            timer_clk_en = 1;
            gpu_ready_o = 1;

            if (timer_done) begin // move to next state
              next_state = FETCH_NUM_VRTX;
            end else
              next_state = state;
          end else
            next_state = state;

        end else if (dma_ready_i) begin // data has not been fetched
          gpu_valid_o = 1; // req the address
          next_state = WAIT_DMA; // wait for data
        end
      
      end

      FETCH_NUM_VRTX : begin
        if (data_has_been_fetched) begin

          timer_en = 1;
          timer_preload = dma_data_i - 1;
          counter_preload_val = 8'd3;
          counter_preload = 1'd1;
          en_gpu_address_reg = 1;
          en_data_has_been_fetched = 1; // set to 0
          gpu_ready_o = 1; // tell dma we rcvd

          next_state = FETCH_VERTEX;

        end else if (dma_ready_i) begin // data has not been fetched
          gpu_valid_o = 1; // req the address
          next_state = WAIT_DMA; // wait for data
        end
      
      end

      FETCH_VERTEX : begin
        if (data_has_been_fetched) begin

          if (xform_ready) begin
            xform_valid_i = 1; // might have to move this outside the if for true ready valid
            en_gpu_address_reg = 1;
            en_data_has_been_fetched = 1; // set to 0
            timer_clk_en = 1;
            counter_en = 1;
            gpu_ready_o = 1;

            if (counter_done) begin // move to next state
              next_state = FETCH_NORMAL;
              counter_preload_val <= 8'd2;
              counter_preload <= 1'd1;
            end else
              next_state = state;
          end else
            next_state = state;

        end else if (dma_ready_i) begin // data has not been fetched
          gpu_valid_o = 1; // req the address
          next_state = WAIT_DMA; // wait for data
        end
      
      end

      FETCH_NORMAL : begin
        if (data_has_been_fetched) begin

          if (shade_ready) begin

            shade_valid_i = 1; // might have to move this outside the if for true ready valid
            en_gpu_address_reg = 1;
            en_data_has_been_fetched = 1; // set to 0
            timer_clk_en = 1;
            counter_en = 1;
            gpu_ready_o = 1;

            if      (timer_done)
              next_state = IDLE; // done! :)
            else if (counter_done) begin // move to next state
              next_state = FETCH_VERTEX;
              counter_preload_val <= 8'd3;
              counter_preload <= 1'd1;
            end else
              next_state = state;

          end else
            next_state = state;

        end else if (dma_ready_i) begin // data has not been fetched
          gpu_valid_o = 1; // req the address
          next_state = WAIT_DMA; // wait for data
        end
      
      end

      WAIT_DMA : begin
        if (dma_valid_i) begin
          en_data_has_been_fetched = 1; // set to 1
          next_state = return_state; // return to caller
        end else 
          next_state = state;
      end

      default: begin
        next_state = XXX;
      end
    endcase


  end

endmodule

module v_xform (
  input clk, reset,
  input [26:0] data,
  input valid_i,
  input ready_i,

  output ready_o,
  output valid_o,
  output [107:0] vertex_xyzw
);

  // general purpose counter
  wire [7:0] timer_value;
  wire [7:0] timer_preload_val;
  wire timer_done;
  reg timer_en;
  wire timer_preload, timer_reset;
  timer_en #(8, 1) ct0 (
    .en(timer_en),
    .preload(timer_preload),
    .preload_val(timer_preload_val),
    .value(timer_value),
    .done(timer_done),
    .reset(reset || timer_reset),
    .*
  );

  // transform matrix
  reg [26:0] m11, m12, m13, m14;
  reg [26:0] m21, m22, m23, m24;
  reg [26:0] m31, m32, m33, m34;
  reg [26:0] m41, m42, m43, m44; 

  // 16 to 1 mux for xform matrix
  wire load_mat;
  always_ff @(posedge clk ) begin : mat_aq_mux
    // maintain current value by default
    m11 <= m11; m12 <= m12; m13 <= m13; m14 <= m14;
    m21 <= m21; m22 <= m22; m23 <= m23; m24 <= m24;
    m31 <= m31; m32 <= m32; m33 <= m33; m34 <= m34;
    m41 <= m41; m42 <= m42; m43 <= m43; m44 <= m44;
    if (load_mat) begin
      case (timer_value)
        8'd00 : m11 <= data;
        8'd01 : m12 <= data; 
        8'd02 : m13 <= data; 
        8'd03 : m14 <= data; 
        8'd04 : m21 <= data; 
        8'd05 : m22 <= data; 
        8'd06 : m23 <= data; 
        8'd07 : m24 <= data; 
        8'd08 : m31 <= data; 
        8'd09 : m32 <= data;
        8'd10 : m33 <= data;
        8'd11 : m34 <= data;
        8'd12 : m41 <= data;
        8'd13 : m42 <= data;
        8'd14 : m43 <= data;
        8'd15 : m44 <= data;
      endcase
    end
  end

  wire [26:0] l0_result;
  wire lane_valid_i;
  wire l0_valid, l1_valid, l2_valid, l3_valid;
  wire l0_ready, l1_ready, l2_ready, l3_ready;
  wire w_norm_ready;
  xform_lane l0 (
    .m1(m11), .m2(m12), 
    .m3(m13), .m4(m14),
    .v(data),
    .result(l0_result),
    .valid_i(lane_valid_i && l0_ready),
    .valid_o(l0_valid),
    .ready_i(w_norm_ready),
    .ready_o(l0_ready),
    .*
  );

  wire [26:0] l1_result;
  xform_lane l1 (
    .m1(m21), .m2(m22), 
    .m3(m23), .m4(m24),
    .v(data),
    .result(l1_result),
    .valid_i(lane_valid_i && l1_ready),
    .valid_o(l1_valid),
    .ready_i(w_norm_ready),
    .ready_o(l1_ready),
    .*
  );

  wire [26:0] l2_result;
  xform_lane l2 (
    .m1(m31), .m2(m32), 
    .m3(m33), .m4(m34),
    .v(data),
    .result(l2_result),
    .valid_i(lane_valid_i && l2_ready),
    .valid_o(l2_valid),
    .ready_i(w_norm_ready),
    .ready_o(l2_ready),
    .*
  );

  wire [26:0] l3_result;
  xform_lane l3 (
    .m1(m41), .m2(m42), 
    .m3(m43), .m4(m44),
    .v(data),
    .result(l3_result),
    .valid_i(lane_valid_i && l3_ready),
    .valid_o(l3_valid),
    .ready_i(w_norm_ready),
    .ready_o(l3_ready),
    .*
  );

  wire lane_valid_o = l0_valid && l1_valid && l2_valid && l3_valid;
  wire [26:0] x_o, y_o, z_o, w_o;
  wire norm_valid_o;
  w_norm w_norm_inst (
    .x(l0_result),
    .y(l1_result),
    .z(l2_result),
    .w(l3_result),
    .valid_i(lane_valid_o && w_norm_ready),
    .valid_o(norm_valid_o),
    .ready_o(w_norm_ready),
    .eof(1'b0),
    .*
  );

  // state machine
  v_xform_sm sm0 (.*);
  assign vertex_xyzw = {x_o, y_o, z_o, w_o};
  assign ready_o = l0_ready && l1_ready && l2_ready && l3_ready;
  assign valid_o = norm_valid_o;

endmodule

module v_xform_sm (
  input clk, reset,
  input valid_i,
  input [7:0] timer_value,

  output reg load_mat,
  output reg timer_en,
  output reg timer_reset,
  output reg lane_valid_i
);

  // abstract state 
  typedef enum logic [2:0] {
    RESET,
    IDLE,
    FETCH_MAT,
    RUN,
    XXX
  } state_e;

  state_e state, next_state, prev_state;
  always_ff @( posedge clk ) begin : state_logic
    if (reset) state <= RESET;
    else state <= next_state;
    prev_state <= state;
  end

  always_comb begin : next_state_logic

    next_state = RESET;

    timer_en = 0;
    timer_reset = 0;
    load_mat = 0;
    lane_valid_i = 0;

    case ({state})
      RESET : next_state = IDLE;

      IDLE : begin

        if (valid_i) begin
          next_state = FETCH_MAT;
          load_mat = 1;
          timer_en = 1;
        end else begin
          timer_reset = 1;
          next_state = state;
        end

      end

      FETCH_MAT : begin

        if (timer_value > 8'd15) 
          next_state = RUN;
        else begin
          next_state = state;
          if (valid_i) begin
            load_mat = 1;
            timer_en = 1;
          end
        end
      end

      RUN : begin
        next_state = state;
        lane_valid_i = valid_i;
      end

      default : next_state = XXX;
    endcase

  end
  
endmodule

module xform_lane (
  input clk, reset,
  input valid_i, ready_i,
  input [26:0] m1, m2, m3, m4, v,
  output [26:0] result,
  output reg valid_o,
  output reg ready_o
);

  localparam FRACTIONAL_BITS = 14;

  // general purpose counter
  wire [2:0] timer_value;
  wire [2:0] timer_preload_val = 3'd0;
  wire timer_done;
  reg timer_preload = 1'b0;
  reg timer_reset;
  timer_en #(3, 1) time0 (
    .en(valid_i && ready_o),
    .preload(timer_preload),
    .preload_val(timer_preload_val),
    .value(timer_value),
    .done(timer_done),
    .reset(timer_reset || reset),
    .*
  );

  logic [53:0] madd_result;  //  result.result
  logic [26:0] dataa_0; // dataa_0.dataa_0
  logic [26:0] datab_0; // datab_0.datab_0
  logic [ 0:0] ena0;
  logic [ 0:0] sclr0;
  madd madd0(
    .clock0(clk),
    .result(madd_result),
    .dataa_0(dataa_0),
    .datab_0(datab_0),
    .ena0(ena0),
    .sclr0(sclr0)
  );

  wire [53:0] result_intermediate = madd_result >>> FRACTIONAL_BITS;
  assign result = result_intermediate[26:0]; 

  // state machine
  // abstract state 
  typedef enum logic [2:0] {
    RESET,
    IDLE,
    MULT,
    RESULT,
    WAIT,
    VALID,
    XXX
  } state_e;

  state_e state, next_state;
  always_ff @( posedge clk ) begin : state_logic
    if (reset) state <= RESET;
    else state <= next_state;
  end

  always_comb begin : next_state_logic

    next_state = RESET;

    case ({state})
      RESET : next_state = IDLE;

      IDLE : begin
        if (valid_i)
          next_state = MULT;
        else 
          next_state = state;
      end

      MULT : begin
        if (timer_value == 3'd4)
          next_state = RESULT;
        else
          next_state = state;
      end

      RESULT : begin
        next_state = ready_i ? VALID : WAIT;
      end

      WAIT : begin
        next_state = ready_i ? VALID : state;
      end

      VALID : begin
        next_state = ready_i ? IDLE : WAIT;
      end

      default : next_state = XXX;
    endcase

  end

  always_ff @( posedge clk ) begin : output_logic
    dataa_0 <= v;
    datab_0 <= m1;
    ena0 <= 1'd0;
    sclr0 <= 0;
    ready_o <= 0;
    valid_o <= 0;
    timer_reset <= 0;

    case (next_state)
      IDLE : begin

        // tell upstream we're ready
        ready_o <= 1;

        // reset the multiplier when entering IDLE from VALID
        // timer_val will be non zero
        if (state == VALID) begin
          sclr0 <= 1;
          ena0 <= 1;
        end
      end 

      MULT : begin
        // we're still ready to receive data
        ready_o <= 1;

        if (valid_i) begin
          ena0 <= 1'b1;
          if (timer_value == 4'd0)
            datab_0 <= m1;
          else if (timer_value == 4'd1)
            datab_0 <= m2;
          else if (timer_value == 4'd2)
            datab_0 <= m3;
          else
            datab_0 <= m4;
        end

      end

      RESULT : begin
        ready_o <= 0;
        ena0 <= 1;
        datab_0 <= 0;
      end

      WAIT : begin
        ena0 <= 1'b0;
        ready_o <= 1'b0;
        valid_o <= 1'b0;
        timer_reset <= 1'b0;
      end

      VALID : begin
        if (ready_i) begin
          valid_o <= 1'b1;
          timer_reset <= 1'b1;
        end else begin
          ena0 <= 1'b0;
          ready_o <= 1'b0;
          valid_o <= 1'b0;
          timer_reset <= 1'b0;
        end
      end
    endcase

    if (reset) begin
      sclr0 <= 1'b1;
      ena0 <= 1'b1;
      ready_o <= 0;
      valid_o <= 0;
      timer_reset <= 0;
    end

  end

endmodule

module w_norm (
  input clk, reset,
  input [26:0] x, y, z, w,
  input valid_i,
  input ready_i,
  input eof, 

  output reg ready_o,
  output reg valid_o,
  output reg [26:0] x_o, y_o, z_o, w_o
);

  // inputs (registed at output of madd)
  wire [40:0] x_numer = x <<< 14;
  wire [40:0] y_numer = y <<< 14;
  wire [40:0] z_numer = z <<< 14;
  wire [26:0] denom = w;

  wire [40:0] x_quotient, y_quotient, z_quotient;
  wire [26:0] remain;

  reg div_clken;
  wire div_valid;
  div div_x (
    .clock(clk),
    .clken(div_clken),
    .numer(x_numer),
    .denom(denom),
    .quotient(x_quotient),
    .remain(),
    .aclr(1'b0)
  );

  div div_y (
    .clock(clk),
    .clken(div_clken),
    .numer(y_numer),
    .denom(denom),
    .quotient(y_quotient),
    .remain(),
    .aclr(1'b0)
  );

  div div_z (
    .clock(clk),
    .clken(div_clken),
    .numer(z_numer),
    .denom(denom),
    .quotient(z_quotient),
    .remain(),
    .aclr(1'b0)
  );

  reg fifo_rdreq, fifo_wrreq; 
  wire [4:0] fifo_used;
  fifo_1x20 fifo (
    .clock(clk),
    .sclr(reset),
    .data(valid_i),
    .rdreq(fifo_rdreq),
    .wrreq(fifo_wrreq),
    .q(div_valid),
    .usedw(fifo_used)
  );

  // outputs are registered
  always_ff @( posedge clk ) begin        
    x_o <= reset ? 27'd0 : x_quotient[26:0];
    y_o <= reset ? 27'd0 : y_quotient[26:0];
    z_o <= reset ? 27'd0 : z_quotient[26:0];
    w_o <= reset ? 27'd0 : 27'b1 << 14;
  end

  // state machine
  typedef enum logic [2:0] {
    RESET,
    IDLE,
    RUN,
    WAIT,
    EOF,
    XXX
  } state_e;

  state_e state, next_state;
  always_ff @( posedge clk ) begin : state_logic
    if (reset) state <= RESET;
    else state <= next_state;
  end

  always_comb begin : next_state_logic

    next_state = RESET;

    case ({state})
      RESET : next_state = IDLE;

      IDLE : begin
        if (fifo_used >= 5'd18)
          next_state = RUN;
        else
          next_state = state;
      end

      RUN : begin
        // if (~ready_i)
        //     next_state = WAIT;
        // else
          next_state = eof ? EOF : state;
      end

      // WAIT : begin
      //     next_state = ready_i ? RUN : state;
      // end

      EOF : begin
        next_state = state;
      end

      default : next_state = XXX;
    endcase

  end

  always_ff @( posedge clk ) begin : output_logic

    fifo_rdreq <= 1'b0;
    fifo_wrreq <= 1'b1;
    ready_o <= 1'b1;
    div_clken <= 1'b1;
    valid_o <= 1'b0;

    case ({next_state})

      RUN : begin

        if (ready_i) begin
          /* slight hack - helps prevent double capturing 
             of div_valid when div_valid is high and the pipeline
             is resuming from a stall */
          valid_o <= div_valid && div_clken;
          fifo_rdreq <= 1'b1;
        end
        else begin
          div_clken <= 1'b0;
          fifo_rdreq <= 1'b0;
          ready_o <= 1'b0;
          valid_o <= 1'b0;
          fifo_wrreq <= 1'b0;
        end

      end

      // default: 
    endcase
    
    if (reset) begin
      fifo_rdreq <= 1'b0;
      fifo_wrreq <= 1'b0;
      ready_o <= 1'b0;
      div_clken <= 1'b0;
      valid_o <= 1'b0;
    end
  end

endmodule

