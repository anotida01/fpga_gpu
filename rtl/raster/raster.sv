`timescale 1ps/1ps

module raster (
  input clk, reset,

  input [107:0] v_fifo_q,
  input v_fifo_empty,
  output v_fifo_rdreq,

  input [26:0] vn_fifo_q,
  input vn_fifo_empty,
  output vn_fifo_rdreq,

  // output pixel data
  output [26:0] c0_o, c1_o, c2_o,

  // output barycentric coeffs
  output [31:0] w0_o, w1_o, w2_o,
  output [31:0] x_o, y_o,

  input ready_i,
  output valid_o

);
  
  // triangles
  wire [26:0] v0_x_i, v0_y_i, v0_z_i;
  wire [26:0] v1_x_i, v1_y_i, v1_z_i;
  wire [26:0] v2_x_i, v2_y_i, v2_z_i;
  wire [26:0] c0_i, c1_i, c2_i;

  // orientation corrected triangles
  wire [26:0] v0_x, v0_y, v0_z;
  wire [26:0] v1_x, v1_y, v1_z;
  wire [26:0] v2_x, v2_y, v2_z;
  wire [26:0] c0, c1, c2; 

  wire v_fetch_ready, v_fetch_valid;
  wire v_cw_ready, v_cw_valid;

  // fetches xformed vertices and constructs triangles
  v_fetch v_fetch0 (
    .ready_o(v_fetch_ready),
    .ready_i(v_cw_ready),
    .valid_o(v_fetch_valid),
    .*
  );

  // organizes triangle vertices in CW order
  wire inv_z_ready;
  wire rstr_ready;
  v_cw v_cw0 (
    .v0_x_o(v0_x), .v0_y_o(v0_y), .v0_z_o(v0_z),
    .v1_x_o(v1_x), .v1_y_o(v1_y), .v1_z_o(v1_z),
    .v2_x_o(v2_x), .v2_y_o(v2_y), .v2_z_o(v2_z),
    .c0_o(c0), .c1_o(c1), .c2_o(c2),

    .ready_i(inv_z_ready && rstr_ready),
    .valid_i(v_fetch_valid),
    .ready_o(v_cw_ready),
    .valid_o(v_cw_valid),
    .*
  );

  // pre invert z vertices 
  wire [31:0] inv_z_v0_z, inv_z_v1_z, inv_z_v2_z;
  wire inv_z_fifo_empty, inv_z_fifo_rdreq;
  inv_z inv_z0 (
    // input vertices
    .v0_z_i(v0_z), 
    .v1_z_i(v1_z), 
    .v2_z_i(v2_z),

    // output vertices
    .v0_z_o(inv_z_v0_z),
    .v1_z_o(inv_z_v1_z),
    .v2_z_o(inv_z_v2_z),

    // DEBUG
    .fifo_rdreq(inv_z_fifo_rdreq),
    .fifo_empty(inv_z_fifo_empty),

    .valid_i(v_cw_valid),
    .ready_o(inv_z_ready),
    .*
  );

  // compute triangle bounding box
  wire [26:0] bb_max_x, bb_min_x;
  wire [26:0] bb_max_y, bb_min_y;
  wire bb_ready, bb_valid;
  bound_box bb0 (
    .v0_x_i, .v0_y_i,
    .v1_x_i, .v1_y_i,
    .v2_x_i, .v2_y_i,

    .max_x(bb_max_x), .min_x(bb_min_x),
    .max_y(bb_max_y), .min_y(bb_min_y),

    .ready_i(rstr_ready), .valid_i(v_fetch_valid),
    .ready_o(bb_ready), .valid_o(bb_valid),
    .*
  );

  // main raster loop
  wire [26:0] v0_z_rstr;
  wire [26:0] v1_z_rstr;
  wire [26:0] v2_z_rstr;
  wire [26:0] c0_rstr, c1_rstr, c2_rstr; 
  wire [31:0] w0_rstr, w1_rstr, w2_rstr, area_rstr;
  wire [31:0] x_rstr, y_rstr;
  wire rstr_valid;
  wire depth_ready;
  raster_loop rstr_loop0 (
    // bounding box
    .max_x_i(bb_max_x), .min_x_i(bb_min_x),
    .max_y_i(bb_max_y), .min_y_i(bb_min_y),

    // input triangle x & y & c
    .v0_x_i(v0_x), .v0_y_i(v0_y), .c0_i(c0),
    .v1_x_i(v1_x), .v1_y_i(v1_y), .c1_i(c1),
    .v2_x_i(v2_x), .v2_y_i(v2_y), .c2_i(c2),

    // input triangle 1/z
    .v0_z_i(inv_z_v0_z),
    .v1_z_i(inv_z_v1_z),
    .v2_z_i(inv_z_v2_z),
    .inv_z_fifo_empty_i(inv_z_fifo_empty),
    .inv_z_fifo_rdreq(inv_z_fifo_rdreq),

    // output triangles
    // .v0_x_o(v0_x_rstr), .v0_y_o(v0_y_rstr), 
    .v0_z_o(v0_z_rstr),
    // .v1_x_o(v1_x_rstr), .v1_y_o(v1_y_rstr), 
    .v1_z_o(v1_z_rstr),
    // .v2_x_o(v2_x_rstr), .v2_y_o(v2_y_rstr), 
    .v2_z_o(v2_z_rstr),
    .c0_o(c0_rstr), .c1_o(c1_rstr), .c2_o(c2_rstr),

    // barycentric coeffs & passing co-ords x & y
    .w0_o(w0_rstr), .w1_o(w1_rstr), .w2_o(w2_rstr),
    .area(area_rstr),
    .x_o(x_rstr), .y_o(y_rstr),

    .ready_i(1'b1), 
    .valid_i(bb_valid && v_cw_valid),
    .valid_o(rstr_valid),
    .ready_o(rstr_ready),
    .*
  );

  wire [26:0] c0_depth, c1_depth, c2_depth; 
  wire [31:0] w0_depth, w1_depth, w2_depth;
  wire [31:0] x_depth, y_depth;
  wire depth_valid;
  depth depth0 (
    // input triangles
    .v0_z_i(v0_z_rstr),
    .v1_z_i(v1_z_rstr),
    .v2_z_i(v2_z_rstr),
    .c0_i(c0_rstr),
    .c1_i(c1_rstr),
    .c2_i(c2_rstr),

    // barycentric coeffs
    .w0_i(w0_rstr), .w1_i(w1_rstr), .w2_i(w2_rstr),
    .area_i(area_rstr),
    .x_i(x_rstr), .y_i(y_rstr),

    // output pixel data
    .c0_o(c0_depth), .c1_o(c1_depth), .c2_o(c2_depth),
    .x_o(x_depth), .y_o(y_depth),

    // output barycentric coeffs
    .w0_o(w0_depth), .w1_o(w1_depth), .w2_o(w2_depth),

    .ready_i(ready_i), .valid_i(rstr_valid),
    .ready_o(depth_ready), .valid_o(depth_valid),
    .*
  );

  assign {c0_o, c1_o, c2_o} = {c0_depth, c1_depth, c2_depth};
  assign {w0_o, w1_o, w2_o} = {w0_depth, w1_depth, w2_depth};
  assign {x_o, y_o} = {x_depth, y_depth};
  assign valid_o = depth_valid;

endmodule


// fetches xformed vertices and constructs triangles
module v_fetch (
  input clk, reset,

  // vertex fifo
  input [107:0] v_fifo_q,
  input v_fifo_empty,
  output reg v_fifo_rdreq,

  // vertex normal fifo 
  input [26:0] vn_fifo_q,
  input vn_fifo_empty,
  output reg vn_fifo_rdreq,

  // triangle outputs
  output reg [26:0] v0_x_i, v0_y_i, v0_z_i,
  output reg [26:0] v1_x_i, v1_y_i, v1_z_i,
  output reg [26:0] v2_x_i, v2_y_i, v2_z_i,
  output reg [26:0] c0_i, c1_i, c2_i,

  // valid-ready
  input ready_i,
  output reg ready_o, valid_o

);

  // general purpose counter
  wire [7:0] timer_value;
  reg [7:0] timer_preload_val;
  wire timer_done;
  reg timer_en;
  reg timer_preload, timer_reset;
  timer_en #(8, 1) ct0 (
    .en(timer_en),
    .preload(timer_preload),
    .preload_val(timer_preload_val),
    .value(timer_value),
    .done(timer_done),
    .reset(reset || timer_reset),
    .*
  );

  reg load_en;
  reg [26:0] w;
  always_ff @( posedge clk ) begin : data_regs
    
    v0_x_i <= v0_x_i; v0_y_i <= v0_y_i; v0_z_i <= v0_z_i;
    v1_x_i <= v1_x_i; v1_y_i <= v1_y_i; v1_z_i <= v1_z_i;
    v2_x_i <= v2_x_i; v2_y_i <= v2_y_i; v2_z_i <= v2_z_i;
    c0_i <= c0_i; c1_i <= c1_i; c2_i <= c2_i;

    if (load_en) begin
      case ({timer_value})
        8'd0 : begin
          { v0_x_i, v0_y_i, v0_z_i, w } <= v_fifo_q;
          c0_i <= vn_fifo_q;
        end
        8'd1 : begin
          { v1_x_i, v1_y_i, v1_z_i, w } <= v_fifo_q;
          c1_i <= vn_fifo_q;
        end 
        8'd2 : begin
          { v2_x_i, v2_y_i, v2_z_i, w } <= v_fifo_q;
          c2_i <= vn_fifo_q;
        end 
      endcase
    end

  end


  // state machine
  typedef enum logic[2:0] {
    RESET,
    IDLE,
    LOAD,
    VALID,
    XXX
  } state_e;

  state_e state, next_state;
  always_ff @( posedge clk ) begin : state_reg
    state <= reset ? RESET : next_state;
  end

  always_comb begin

    // default
    next_state = XXX;

    timer_en = 0;
    timer_preload = 0;
    timer_preload_val = 8'd0;
    timer_reset = 0;

    vn_fifo_rdreq = 0;
    v_fifo_rdreq = 0;

    load_en = 0;

    ready_o = 1;
    valid_o = 0;

    case ({state})
      RESET : begin
        next_state = IDLE;
      end 

      IDLE : begin
        next_state = state;
        if (~v_fifo_empty && ~vn_fifo_empty) begin
          next_state = LOAD;
          vn_fifo_rdreq = 1;
          v_fifo_rdreq = 1;
        end
      end

      LOAD : begin
        timer_en = 1;
        load_en = 1;
        ready_o = 0;
        if (timer_value == 8'd2)
          next_state = VALID;
        else
          next_state = IDLE;
      end

      VALID : begin
        ready_o = 0;
        next_state = state;
        if (ready_i) begin
          valid_o = 1;
          timer_reset = 1;
          next_state = IDLE;
        end
      end

    endcase

  end


endmodule


// organizes vertices in CW order
// organized for 3 cycle delay
module v_cw(
  input clk, reset,

  input [26:0] v0_x_i, v0_y_i, v0_z_i,
  input [26:0] v1_x_i, v1_y_i, v1_z_i,
  input [26:0] v2_x_i, v2_y_i, v2_z_i,
  input [26:0] c0_i, c1_i, c2_i,

  output logic [26:0] v0_x_o, v0_y_o, v0_z_o,
  output logic [26:0] v1_x_o, v1_y_o, v1_z_o,
  output logic [26:0] v2_x_o, v2_y_o, v2_z_o,
  output logic [26:0] c0_o, c1_o, c2_o,

  input ready_i, valid_i,
  output reg ready_o, valid_o

);
  reg en_i_regs;
  reg [26:0] v0_x, v0_y, v0_z;
  reg [26:0] v1_x, v1_y, v1_z;
  reg [26:0] v2_x, v2_y, v2_z;
  reg [26:0] c0, c1, c2;
  always_ff @( posedge clk ) begin : input_regs

    v0_x <= v0_x; v0_y <= v0_y; v0_z <= v0_z;
    v1_x <= v1_x; v1_y <= v1_y; v1_z <= v1_z;
    v2_x <= v2_x; v2_y <= v2_y; v2_z <= v2_z;
    c0 <= c0; c1 <= c1; c2 <= c2;

    if (valid_i && en_i_regs) begin
      v0_x <= v0_x_i; v0_y <= v0_y_i; v0_z <= v0_z_i;
      v1_x <= v1_x_i; v1_y <= v1_y_i; v1_z <= v1_z_i;
      v2_x <= v2_x_i; v2_y <= v2_y_i; v2_z <= v2_z_i;
      c0 <= c0_i; c1 <= c1_i; c2 <= c2_i;
    end

    if (reset) begin
      v0_x <= 27'd0; v0_y <= 27'd0; v0_z <= 27'd0;
      v1_x <= 27'd0; v1_y <= 27'd0; v1_z <= 27'd0;
      v2_x <= 27'd0; v2_y <= 27'd0; v2_z <= 27'd0;
      c0 <= 27'd0; c1 <= 27'd0; c2 <= 27'd0;
    end

  end

  // fixed val = (v2.x - v1.x)*(v1.y - v0.y) - (v1.x - v0.x)*(v2.y - v1.y);
  logic signed [53:0] mult1_inter, mult2_inter;
  logic signed [53:0] mult1_shift, mult2_shift;
  logic signed [31:0] mult1, mult2;
  logic signed [31:0] val;

  assign mult1 = mult1_shift[31:0];
  assign mult2 = mult2_shift[31:0];
  
  always_comb begin : mult
    mult1_inter = (v2_x - v1_x) * (v1_y - v0_y);
    mult1_shift = mult1_inter >>> 14;
    mult2_inter = (v1_x - v0_x) * (v2_y - v1_y);
    mult2_shift = mult2_inter >>> 14;
  end

  always_ff @(posedge clk) begin : mult_reg
    val <= reset ? 32'sd0 : mult1 - mult2;
  end

  reg swap;
  always_ff @( posedge clk ) begin : out_regs
    v0_x_o <= v0_x; v0_y_o <= v0_y; v0_z_o <= v0_z;
    v1_x_o <= v1_x; v1_y_o <= v1_y; v1_z_o <= v1_z;
    v2_x_o <= v2_x; v2_y_o <= v2_y; v2_z_o <= v2_z;
    c0_o <= c0; c1_o <= c1; c2_o <= c2;

    if (swap) begin
      v1_x_o <= v2_x; v1_y_o <= v2_y; v1_z_o <= v2_z;
      v2_x_o <= v1_x; v2_y_o <= v1_y; v2_z_o <= v1_z;
      c1_o <= c2; c2_o <= c1;
    end

  end


  // state machine
  typedef enum logic[2:0] {
    RESET,
    IDLE,
    MULT,
    TEST,
    VALID,
    XXX
  } state_e;

  state_e state, next_state;
  always_ff @( posedge clk ) begin : state_reg
    state <= reset ? RESET : next_state;
  end

  always_comb begin

    // default
    next_state = XXX;
    en_i_regs = 0;
    ready_o = 1;
    valid_o = 0;
    swap = 0;

    case ({state})
      RESET : begin
        next_state = IDLE;
      end 

      IDLE : begin
        next_state = state;
        if (valid_i) begin
          en_i_regs = 1;
          next_state = MULT;
        end
      end

      MULT : begin
        ready_o = 0;
        next_state = TEST;
      end

      TEST : begin
        ready_o = 0;
        next_state = VALID;
        if (val < 32'sd0)
          swap = 1'd1;
      end

      VALID : begin
        ready_o = 0;
        next_state = state;

        if (val < 27'sd0)
          swap = 1'd1;

        if (ready_i) begin
          valid_o = 1;
          next_state = IDLE;
        end

      end
    endcase

  end

endmodule

// find the bouding box of a triangle
// organized for 3 cycle delay
module bound_box (
  input clk, reset,

  input [26:0] v0_x_i, v0_y_i,
  input [26:0] v1_x_i, v1_y_i,
  input [26:0] v2_x_i, v2_y_i,

  output reg [26:0] max_x, min_x,
  output reg [26:0] max_y, min_y,

  input ready_i, valid_i,
  output reg ready_o, valid_o

);
  
  reg en_i_regs;
  reg [26:0] v0_x, v0_y;
  reg [26:0] v1_x, v1_y;
  reg [26:0] v2_x, v2_y;
  always_ff @( posedge clk ) begin : input_regs

    v0_x <= v0_x; v0_y <= v0_y;
    v1_x <= v1_x; v1_y <= v1_y;
    v2_x <= v2_x; v2_y <= v2_y;

    if (valid_i && en_i_regs) begin
      v0_x <= v0_x_i; v0_y <= v0_y_i;
      v1_x <= v1_x_i; v1_y <= v1_y_i;
      v2_x <= v2_x_i; v2_y <= v2_y_i;
    end

    if (reset) begin
      v0_x <= 27'd0; v0_y <= 27'd0;
      v1_x <= 27'd0; v1_y <= 27'd0;
      v2_x <= 27'd0; v2_y <= 27'd0;
    end

  end

  // 3 cycle delay
  // cc1: input valid
  // cc2: cmp 1
  // cc3: cmp 2
  // cc4: output valid

  // abstract state 
  typedef enum logic [2:0] {
    RESET,
    IDLE,
    CMP_1,
    CMP_2,
    VALID,
    XXX
  } state_e;

  state_e state, next_state;
  always_ff @( posedge clk ) begin : state_logic
    state <= reset ? RESET : next_state;
  end

  // intermediate registers
  reg en_m1, en_m2;
  reg [26:0] m1_x, m1_x_in, m2_x, m2_x_in;
  reg [26:0] m1_y, m1_y_in, m2_y, m2_y_in;

  reg en_o;
  reg [26:0] max_x_in, max_y_in, min_x_in, min_y_in;

  always_ff @( posedge clk ) begin
    m1_x <= en_m1 ? m1_x_in : m1_x;
    m2_x <= en_m2 ? m2_x_in : m2_x;
    m1_y <= en_m1 ? m1_y_in : m1_y;
    m2_y <= en_m2 ? m2_y_in : m2_y;

    max_x <= en_o ? max_x_in : max_x;
    max_y <= en_o ? max_y_in : max_y;
    min_x <= en_o ? min_x_in : min_x;
    min_y <= en_o ? min_y_in : min_y;

    if (reset) begin
      m1_x <= 27'd0;
      m2_x <= 27'd0;
      m1_y <= 27'd0;
      m2_y <= 27'd0;
      max_x <= 27'd0;
      max_y <= 27'd0;
      min_x <= 27'd0;
      min_y <= 27'd0;
    end

  end


  always_comb begin : next_state_logic

    next_state = RESET;

    en_i_regs = 0;
    en_m1 = 0;
    en_m2 = 0;
    en_o = 0;

    ready_o = 1;
    valid_o = 0;

    m1_x_in = v0_x;
    m2_x_in = v1_x;
    m1_y_in = v0_y;
    m2_y_in = v1_y;
    max_x_in = m1_x;
    min_x_in = m2_x;
    max_y_in = m1_y;
    min_y_in = m2_y;

    case ({state})

      RESET : next_state = IDLE;

      IDLE : begin

        en_i_regs = 1;

        if (valid_i) begin
          next_state = CMP_1;
        end else begin
          next_state = state;
        end

      end

      CMP_1 : begin

        en_m1 = 1;
        en_m2 = 1;
        valid_o = 0;
        ready_o = 0;

        if (v0_x > v1_x) begin
          m1_x_in = v0_x;
          m2_x_in = v1_x;
        end else begin
          m1_x_in = v1_x;
          m2_x_in = v0_x;
        end

        if (v0_y > v1_y) begin
          m1_y_in = v0_y;
          m2_y_in = v1_y;
        end else begin
          m1_y_in = v1_y;
          m2_y_in = v0_y;
        end

        next_state = CMP_2;
        
      end

      CMP_2 : begin
        ready_o = 0;
        valid_o = 0;
        en_o = 1;

        max_x_in = (m1_x > v2_x) ? m1_x : v2_x;
        min_x_in = (m2_x < v2_x) ? m2_x : v2_x;

        max_y_in = (m1_y > v2_y) ? m1_y : v2_y;
        min_y_in = (m2_y < v2_y) ? m2_y : v2_y;

        next_state = VALID;

      end

      VALID : begin
        ready_o = 0;
        next_state = state;

        if (ready_i) begin
          valid_o = 1;
          next_state = IDLE;
        end
        
      end

      default : next_state = XXX;
    endcase

  end

endmodule


// comptures barycentric coefficients for all points inside bounding box
// performs half-plane-test and issues passing co-ordinates for depth testing
module raster_loop (
  input clk, reset,

  // bounding box
  input [26:0] max_x_i, min_x_i,
  input [26:0] max_y_i, min_y_i,

  // input triangle x & y
  input [26:0] v0_x_i, v0_y_i, c0_i,
  input [26:0] v1_x_i, v1_y_i, c1_i,
  input [26:0] v2_x_i, v2_y_i, c2_i,

  // input triangle 1/z
  input [26:0] v0_z_i,
  input [26:0] v1_z_i,
  input [26:0] v2_z_i,
  input inv_z_fifo_empty_i,
  output reg inv_z_fifo_rdreq,

  // output triangles
  output logic [26:0] v0_z_o,
  output logic [26:0] v1_z_o,
  output logic [26:0] v2_z_o,
  output logic [26:0] c0_o, c1_o, c2_o,

  // barycentric coeffs
  output logic [31:0] w0_o, w1_o, w2_o, area,
  output logic [31:0] x_o, y_o,

  input ready_i, valid_i,
  output reg ready_o, valid_o

);
  
  reg [26:0] max_x, min_x;
  reg [26:0] max_y, min_y;
  reg [26:0] v0_x, v0_y, v0_z, c0;
  reg [26:0] v1_x, v1_y, v1_z, c1;
  reg [26:0] v2_x, v2_y, v2_z, c2;
  reg en_bb_xy, en_z;
  always_ff @( posedge clk ) begin : i_regs
    max_x <= reset ? 27'd0 : (en_bb_xy ? max_x_i : max_x);
    max_y <= reset ? 27'd0 : (en_bb_xy ? max_y_i : max_y);
    min_x <= reset ? 27'd0 : (en_bb_xy ? min_x_i : min_x);
    min_y <= reset ? 27'd0 : (en_bb_xy ? min_y_i : min_y);

    v0_x <= reset ? 27'd0 : (en_bb_xy ? v0_x_i : v0_x);
    v1_x <= reset ? 27'd0 : (en_bb_xy ? v1_x_i : v1_x);
    v2_x <= reset ? 27'd0 : (en_bb_xy ? v2_x_i : v2_x);
    v0_y <= reset ? 27'd0 : (en_bb_xy ? v0_y_i : v0_y);
    v1_y <= reset ? 27'd0 : (en_bb_xy ? v1_y_i : v1_y);
    v2_y <= reset ? 27'd0 : (en_bb_xy ? v2_y_i : v2_y);

    c0 <= reset ? 27'd0 : (en_bb_xy ? c0_i : c0);
    c1 <= reset ? 27'd0 : (en_bb_xy ? c1_i : c1);
    c2 <= reset ? 27'd0 : (en_bb_xy ? c2_i : c2);

    v0_z <= reset ? 27'd0 : (en_z ? v0_z_i : v0_z);
    v1_z <= reset ? 27'd0 : (en_z ? v1_z_i : v1_z);
    v2_z <= reset ? 27'd0 : (en_z ? v2_z_i : v2_z);

  end

  assign c0_o = c0;
  assign c1_o = c1;
  assign c2_o = c2;

  assign v0_z_o = v0_z_i;
  assign v1_z_o = v1_z_i;
  assign v2_z_o = v2_z_i;

  // barycentric coefficients
  reg [31:0] w0, w1, w2;
  wire signed [31:0] edge0_o;
  wire signed [31:0] edge1_o;
  wire signed [31:0] edge2_o;
  wire signed [31:0] edge3_o;
  reg en_w, en_area;
  always_ff @(posedge clk ) begin
    w0 <= reset ? 32'd0 : (en_w ? edge0_o : w0);
    w1 <= reset ? 32'd0 : (en_w ? edge1_o : w1);
    w2 <= reset ? 32'd0 : (en_w ? edge2_o : w2);
    area <= reset ? 32'd0 : (en_area ? edge3_o : area);
  end

  logic signed [26:0] i, j;
  wire [26:0] test_x, test_y;
  assign test_x = i + 26'h2000; // i + 0.5
  assign test_y = j + 26'h2000; // j + 0.5

  reg edge_valid;

  // w0
  wire edge0_ready, edge0_valid;
  edge_func edge0 (
    .v0_x_i(v1_x), .v0_y_i(v1_y),
    .v1_x_i(v2_x), .v1_y_i(v2_y),
    .v2_x_i(test_x), .v2_y_i(test_y),
    .val(edge0_o),
    .valid_i(edge_valid),
    .valid_o(edge0_valid),
    .ready_i(1'b1),
    .ready_o(edge0_ready),
    .*
  );

  // w1
  wire edge1_ready, edge1_valid;
  edge_func edge1 (
    .v0_x_i(v2_x), .v0_y_i(v2_y),
    .v1_x_i(v0_x), .v1_y_i(v0_y),
    .v2_x_i(test_x), .v2_y_i(test_y),
    .val(edge1_o),
    .valid_i(edge_valid),
    .valid_o(edge1_valid),
    .ready_i(1'b1),
    .ready_o(edge1_ready),
    .*
  );

  // w2
  wire edge2_ready, edge2_valid;
  edge_func edge2 (
    .v0_x_i(v0_x), .v0_y_i(v0_y),
    .v1_x_i(v1_x), .v1_y_i(v1_y),
    .v2_x_i(test_x), .v2_y_i(test_y),
    .val(edge2_o),
    .valid_i(edge_valid),
    .valid_o(edge2_valid),
    .ready_i(1'b1),
    .ready_o(edge2_ready),
    .*
  );

  // area
  wire edge3_ready, edge3_valid;
  edge_func edge3 (
    .v0_x_i(v0_x), .v0_y_i(v0_y),
    .v1_x_i(v1_x), .v1_y_i(v1_y),
    .v2_x_i(v2_x), .v2_y_i(v2_y),
    .val(edge3_o),
    .valid_i(edge_valid),
    .valid_o(edge3_valid),
    .ready_i(1'b1),
    .ready_o(edge3_ready),
    .*
  );

  // outer counter (i)
  reg i_preload, i_en;
  reg [31:0] i_preload_val;
  wire i_done;
  timer_en #(32, 1, 32'h4000) timer_i (
    .preload(i_preload),
    .en(i_en),
    .preload_val(i_preload_val),
    .value(i),
    .done(i_done),
    .*
  );

  // inner counter (i)
  reg j_preload, j_en;
  reg [31:0] j_preload_val;
  wire j_done;
  timer_en #(32, 1, 32'h4000) timer_j (
    .preload(j_preload),
    .en(j_en),
    .preload_val(j_preload_val),
    .value(j),
    .done(j_done),
    .*
  );

  assign w0_o = w0;
  assign w1_o = w1;
  assign w2_o = w2;
  assign x_o = i;
  assign y_o = j;

  // abstract state 
  typedef enum logic [3:0] {
    RESET,
    IDLE,
    SET_LIMITS,
    FETCH_Z,
    SAVE_Z,
    GET_WX,
    WAIT_WX,
    INC_I,
    INC_J,
    HP_TEST,
    HP_PASS,
    HP_FAIL,
    RUN,
    XXX
  } state_e;

  localparam RASTER_MAX_X = 26'sd320 << 14; // todo: this should be parameterized to FRACTATIONAL_BITS
  localparam RASTER_MAX_Y = 26'sd240 << 14; // todo: this should be parameterized to FRACTATIONAL_BITS

  state_e state, next_state, prev_state;
  always_ff @( posedge clk ) begin : state_logic
    state <= reset ? RESET : next_state;
  end

  always_comb begin : next_state_logic

    next_state = RESET;

    en_w = 0;
    en_area = 0;
    en_bb_xy = 0;
    en_z = 0;

    edge_valid = 0;

    i_preload = 0;
    j_preload = 0;
    i_preload_val = min_x;
    j_preload_val = min_y;
    i_en = 0;
    j_en = 0;

    ready_o = 0;
    valid_o = 0;

    inv_z_fifo_rdreq = 0;

    case ({state})
      RESET: next_state = IDLE; 

      IDLE : begin
        next_state = state;
        ready_o = 1;
        if (valid_i) begin
          en_bb_xy = 1;
          next_state = SET_LIMITS;
        end
      end

      SET_LIMITS : begin

        next_state = FETCH_Z;

        // set minimum limits
        i_preload = 1;
        j_preload = 1;
        i_preload_val = min_x;
        j_preload_val = min_y;
      end

      FETCH_Z : begin
        next_state = state; // wait for 1/z
        if (~inv_z_fifo_empty_i) begin
          inv_z_fifo_rdreq = 1;
          next_state = SAVE_Z;
        end
      end

      SAVE_Z : begin
        // this logic captures situations where bounding box func returns values that are off screen
        // not sure if we've encountered a bug that this code fixes... still, it feels right
        // if ((i > RASTER_MAX_X) || (i < 26'sd0) || (j > RASTER_MAX_Y) || (j < 26'sd0))
        //   next_state = IDLE;
        if ((max_x > RASTER_MAX_X) || (max_y > RASTER_MAX_Y)) // this fixes the vertical lines issue
          next_state = IDLE;
        else begin
          next_state = GET_WX;
          en_z = 1;
        end
      end

      GET_WX : begin
        next_state = WAIT_WX;
        // start computing coeffs
        edge_valid = 1;
      end

      WAIT_WX : next_state = HP_TEST;

      HP_TEST : begin
        if (edge0_o >= 32'sd0 && edge1_o >= 32'sd0 && edge2_o >= 32'sd0) begin
          next_state = HP_PASS;
          en_w = 1;
          en_area = 1;
        end else 
          next_state = INC_J;
      end

      HP_PASS : begin
        next_state = state;
        if (ready_i) begin
          next_state = INC_J;
          valid_o = 1;
        end
      end

      HP_FAIL : 
        next_state = INC_J;

      INC_J : begin
        if ((j <= max_y) && (j <= RASTER_MAX_Y)) begin
          j_en = 1;
          next_state = GET_WX;
        end else
          next_state = INC_I;
      end

      INC_I : begin
        if ((i <= max_x) && (i <= RASTER_MAX_X)) begin
          i_en = 1;
          j_preload_val = min_y;
          j_preload = 1;
          next_state = GET_WX;
        end else begin
          next_state = IDLE;
        end
      end

      default: next_state = XXX;
    endcase

  end

endmodule

// edge function - 1 cycle delay
module edge_func (
  input clk, reset, 

  input [26:0] v0_x_i, v0_y_i,
  input [26:0] v1_x_i, v1_y_i,
  input [26:0] v2_x_i, v2_y_i,

  output logic signed [31:0] val,

  input ready_i, valid_i,
  output reg ready_o, valid_o

);


  reg en_i_regs;
  reg [26:0] v0_x, v0_y;
  reg [26:0] v1_x, v1_y;
  reg [26:0] v2_x, v2_y;
  always_ff @( posedge clk ) begin : i_regs

    v0_x <= v0_x; v0_y <= v0_y;
    v1_x <= v1_x; v1_y <= v1_y;
    v2_x <= v2_x; v2_y <= v2_y;

    if (valid_i && en_i_regs) begin
      v0_x <= v0_x_i; v0_y <= v0_y_i;
      v1_x <= v1_x_i; v1_y <= v1_y_i;
      v2_x <= v2_x_i; v2_y <= v2_y_i;
    end

    if (reset) begin
      v0_x <= 27'd0; v0_y <= 27'd0;
      v1_x <= 27'd0; v1_y <= 27'd0;
      v2_x <= 27'd0; v2_y <= 27'd0;
    end

  end

  // return (c.x - a.x) * (b.y - a.y) - (b.x - a.x) * (c.y - a.y); // CW
  logic signed [53:0] mult1_inter, mult2_inter;
  logic signed [53:0] mult1_shift, mult2_shift;
  logic signed [31:0] mult1, mult2;
  // logic signed [31:0] val;

  assign mult1 = mult1_shift[31:0];
  assign mult2 = mult2_shift[31:0];
  
  always_comb begin : mult
    mult1_inter = (v2_x - v0_x) * (v1_y - v0_y);
    mult1_shift = mult1_inter >>> 14;
    mult2_inter = (v1_x - v0_x) * (v2_y - v0_y);
    mult2_shift = mult2_inter >>> 14;
  end

  always_ff @(posedge clk) begin : mult_reg
    val <= reset ? 32'sd0 : mult1 - mult2;
  end

  // state machine
  typedef enum logic[2:0] {
    RESET,
    IDLE,
    MULT,
    TEST,
    VALID,
    XXX
  } state_e;

  state_e state, next_state;
  always_ff @( posedge clk ) begin : state_reg
    state <= reset ? RESET : next_state;
  end

  always_comb begin

    // default
    next_state = XXX;
    en_i_regs = 0;
    ready_o = 1;
    valid_o = 0;

    case ({state})
      RESET : begin
        next_state = IDLE;
      end 

      IDLE : begin
        next_state = state;
        if (valid_i) begin
          en_i_regs = 1;
          next_state = MULT;
        end
      end

      MULT : begin
        ready_o = 0;
        next_state = VALID;
      end

      VALID : begin
        ready_o = 0;
        next_state = state;

        if (ready_i) begin
          valid_o = 1;
          next_state = IDLE;
        end

      end
    endcase

  end
endmodule


// pre z inversion
module inv_z (
  input clk, reset,

  // input vertices
  input [26:0] v0_z_i, v1_z_i, v2_z_i,

  // output vertices
  output [31:0] v0_z_o, v1_z_o, v2_z_o,
  input fifo_rdreq,
  output fifo_empty,

  input valid_i,
  output reg ready_o

);

  // inputs (registed at output of v_cw)
  wire [40:0] numer = 40'h1000_0000; // 1 << 28;

  wire [40:0] v0_quotient, v1_quotient, v2_quotient;
  wire [26:0] remain;

  // dividers
  reg div_clken;
  wire div_valid;
  div div_v0 (
    .clock(clk),
    .clken(div_clken),
    .numer(numer),
    .denom(v0_z_i),
    .quotient(v0_quotient),
    .remain(),
    .aclr(1'b0)
  );

  div div_v1 (
    .clock(clk),
    .clken(div_clken),
    .numer(numer),
    .denom(v1_z_i),
    .quotient(v1_quotient),
    .remain(),
    .aclr(1'b0)
  );

  div div_v2 (
    .clock(clk),
    .clken(div_clken),
    .numer(numer),
    .denom(v2_z_i),
    .quotient(v2_quotient),
    .remain(),
    .aclr(1'b0)
  );

  // divider fifos
  reg [31:0] v0_fifo_i, v1_fifo_i, v2_fifo_i;
  reg div_fifo_wrreq;
  wire div_fifo_rdreq = fifo_rdreq;
  wire div_fifo_empty, div_fifo_full;
  assign fifo_empty = div_fifo_empty;

  fifo_32x32 div_v0_fifo (
    .clock(clk),
    .sclr(reset),
    .data(v0_fifo_i),
    .rdreq(div_fifo_rdreq),
    .wrreq(div_fifo_wrreq),
    .empty(div_fifo_empty),
    .full(div_fifo_full),
    .q(v0_z_o)
  );

  fifo_32x32 div_v1_fifo (
    .clock(clk),
    .sclr(reset),
    .data(v1_fifo_i),
    .rdreq(div_fifo_rdreq),
    .wrreq(div_fifo_wrreq),
    // .empty(div_fifo_empty),
    .q(v1_z_o)
  );

  fifo_32x32 div_v2_fifo (
    .clock(clk),
    .sclr(reset),
    .data(v2_fifo_i),
    .rdreq(div_fifo_rdreq),
    .wrreq(div_fifo_wrreq),
    // .empty(div_fifo_empty),
    .q(v2_z_o)
  );

  // valid fifo
  reg valid_fifo_rdreq, valid_fifo_wrreq; 
  wire [4:0] valid_fifo_used;
  fifo_1x20 valid_fifo (
    .clock(clk),
    .sclr(reset),
    .data(valid_i),
    .rdreq(valid_fifo_rdreq),
    .wrreq(valid_fifo_wrreq),
    .q(div_valid),
    .usedw(valid_fifo_used)
  );

  // outputs are registered
  always_ff @( posedge clk ) begin        
    v0_fifo_i <= reset ? 32'd0 : v0_quotient[31:0];
    v1_fifo_i <= reset ? 32'd0 : v1_quotient[31:0];
    v2_fifo_i <= reset ? 32'd0 : v2_quotient[31:0];
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
        if (valid_fifo_used >= 5'd18)
          next_state = RUN;
        else
          next_state = state;
      end

      RUN : begin
          next_state = state;
      end

      EOF : begin
        next_state = state;
      end

      default : next_state = XXX;
    endcase

  end

  always_ff @( posedge clk ) begin : output_logic

    valid_fifo_rdreq <= 1'b0;
    valid_fifo_wrreq <= 1'b1;
    ready_o <= 1'b1;
    div_clken <= 1'b1;
    div_fifo_wrreq <= 1'b0;

    case ({next_state})

      RUN : begin

        if (~div_fifo_full) begin
          /* slight hack - helps prevent double capturing 
             of div_valid when div_valid is high and the pipeline
             is resuming from a stall */
          div_fifo_wrreq <= div_valid && div_clken;
          valid_fifo_rdreq <= 1'b1;
        end
        else begin
          div_clken <= 1'b0;
          valid_fifo_rdreq <= 1'b0;
          ready_o <= 1'b0;
          div_fifo_wrreq <= 1'b0;
          valid_fifo_wrreq <= 1'b0;
        end

      end

      // default: 
    endcase
    
    if (reset) begin
      valid_fifo_rdreq <= 1'b0;
      valid_fifo_wrreq <= 1'b0;
      ready_o <= 1'b0;
      div_clken <= 1'b0;
      div_fifo_wrreq <= 1'b0;
    end
  end


endmodule
