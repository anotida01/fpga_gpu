`ifndef ROP_SCOREBOARD_SV
`define ROP_SCOREBOARD_SV

class rop_scoreboard extends uvm_scoreboard;
  `uvm_analysis_imp_decl(_in)
  `uvm_analysis_imp_decl(_out)

  uvm_analysis_imp_in  #(pipe_item, rop_scoreboard) in_export;
  uvm_analysis_imp_out #(pipe_item, rop_scoreboard) out_export;

  // Expected transaction struct for FIFO queue matching
  typedef struct {
    logic signed [31:0] exp_c;
    logic [31:0]        exp_x;
    logic [31:0]        exp_y;
  } expected_tx_t;

  expected_tx_t exp_q[$];

  int in_count;
  int out_count;
  int mismatch_count;

  `uvm_component_utils(rop_scoreboard)

  function new(string name, uvm_component parent);
    super.new(name, parent);
    in_export  = new("in_export", this);
    out_export = new("out_export", this);
    in_count = 0;
    out_count = 0;
    mismatch_count = 0;
  endfunction

  virtual function void write_in(pipe_item item);
    logic [31:0]        x_i;
    logic [31:0]        y_i;
    logic signed [31:0] w0_i;
    logic signed [31:0] w1_i;
    logic signed [31:0] w2_i;
    logic signed [26:0] c0_raw;
    logic signed [26:0] c1_raw;
    logic signed [26:0] c2_raw;
    logic signed [31:0] c0_i;
    logic signed [31:0] c1_i;
    logic signed [31:0] c2_i;
    logic signed [63:0] p0, p1, p2;
    expected_tx_t tx;

    in_count++;
    x_i  = item.data[31:0];
    y_i  = item.data[63:32];
    w0_i = item.data[95:64];
    w1_i = item.data[127:96];
    w2_i = item.data[159:128];
    c0_raw = item.data[186:160];
    c1_raw = item.data[213:187];
    c2_raw = item.data[240:214];
    c0_i = signed'(c0_raw);
    c1_i = signed'(c1_raw);
    c2_i = signed'(c2_raw);

    p0 = (64'($signed(w0_i) * c0_i)) >>> 14;
    p1 = (64'($signed(w1_i) * c1_i)) >>> 14;
    p2 = (64'($signed(w2_i) * c2_i)) >>> 14;

    tx.exp_c = p0[31:0] + p1[31:0] + p2[31:0];
    tx.exp_x = x_i;
    tx.exp_y = y_i;

    exp_q.push_back(tx);
    `uvm_info("SCB_IN", $sformatf("In tx %0d: x=%0d y=%0d -> exp_c=%0d", 
              in_count, x_i, y_i, tx.exp_c), UVM_MEDIUM)
  endfunction

  virtual function void write_out(pipe_item item);
    logic [31:0] x_o;
    logic [31:0] y_o;
    logic [31:0] c_o;
    expected_tx_t exp;

    out_count++;
    x_o = item.data[31:0];
    y_o = item.data[63:32];
    c_o = item.data[95:64];

    if (exp_q.size() == 0) begin
      `uvm_error("SCB_OUT", $sformatf("Unexpected out transaction: x=%0d y=%0d c=%0d", x_o, y_o, c_o))
      mismatch_count++;
      return;
    end

    exp = exp_q.pop_front();

    if (c_o !== exp.exp_c || x_o !== exp.exp_x || y_o !== exp.exp_y) begin
      `uvm_error("SCB_OUT", $sformatf("Mismatch! Got: x=%0d y=%0d c=%0d | Exp: x=%0d y=%0d c=%0d",
                 x_o, y_o, c_o, exp.exp_x, exp.exp_y, exp.exp_c))
      mismatch_count++;
    end else begin
      `uvm_info("SCB_OUT", $sformatf("Match: x=%0d y=%0d c=%0d", x_o, y_o, c_o), UVM_MEDIUM)
    end
  endfunction

  function void check_phase(uvm_phase phase);
    if (exp_q.size() > 0) begin
      `uvm_error("SCB_CHECK", $sformatf("Unfinished expected transactions in queue: %0d", exp_q.size()))
    end
  endfunction

  function void report_phase(uvm_phase phase);
    `uvm_info("SCB_REPORT", $sformatf("=== ROP Scoreboard Summary ===\n  Inputs processed : %0d\n  Outputs matched  : %0d\n  Mismatches       : %0d\n==============================", 
              in_count, out_count, mismatch_count), UVM_LOW)
  endfunction

endclass

`endif
