
module timer_clk #(
  parameter WIDTH=8
  )(
  input  logic [      0:0] clk, reset, clk_en,
  input  logic [      0:0] preload,
  input  logic [WIDTH-1:0] preload_val,
  output logic [WIDTH-1:0] value,
  output logic [      0:0] timer_done
);

  always_ff @( posedge clk ) begin
    if      ( reset               ) value <= {WIDTH{1'b0}};
    else if ( preload             ) value <= preload_val;
    else if (~timer_done && clk_en) value <= value - 1'b1;
    else                            value <= value;
  end

  // assign timer_done = preload ? 1'b0 : (value == {WIDTH{1'b0}});
  assign timer_done = (value == {WIDTH{1'b0}});

endmodule

module timer_en #(
  parameter WIDTH=8,
  parameter UP=0,
  parameter INC=1'b1
  )(
  input  logic [      0:0] clk, reset,
  input  logic [      0:0] preload, en,
  input  logic [WIDTH-1:0] preload_val,
  output logic [WIDTH-1:0] value,
  output logic [      0:0] done
);

  always_ff @( posedge clk ) begin
    if      ( reset   ) value <= {WIDTH{1'b0}};
    else if ( preload ) value <= preload_val;
    else if ( en      ) begin
      if (UP) 
        value <= value + INC;
      else if (value != 0) // down
        value <= value - INC;
      else 
        value <= value;
    end else            value <= value;
  end

  // assign done = preload ? 1'b0 : (value == {WIDTH{1'b0}});
  assign done = (value == {WIDTH{1'b0}});

endmodule
