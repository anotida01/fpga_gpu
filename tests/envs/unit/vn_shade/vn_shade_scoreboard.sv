`ifndef VN_SHADE_SCOREBOARD_SV
`define VN_SHADE_SCOREBOARD_SV

class vn_shade_scoreboard extends uvm_scoreboard;
  `uvm_analysis_imp_decl(_in)
  `uvm_analysis_imp_decl(_out)

  uvm_analysis_imp_in  #(pipe_item, vn_shade_scoreboard) in_export;
  uvm_analysis_imp_out #(pipe_item, vn_shade_scoreboard) out_export;

  // Latched light vector — input words 1-3 of each frame (Lx, Ly, Lz).
  // Word 4 is a hardware padding word: the DUT's registered control outputs
  // keep ready_o high one cycle past the FSM's light->normal transition,
  // so a 4th word is always accepted and absorbed (multiplied by 0 by the
  // timer_value=3 case of the DUT's light-component select).
  logic signed [26:0] Lx, Ly, Lz;
  bit        light_locked;
  int unsigned light_word_idx;

  // In-progress normal triplet — 3 input words per vertex (nx, ny, nz)
  logic signed [26:0] normal_word [3];
  int unsigned normal_word_idx;

  // Expected output FIFO (Q12.14 signed intensity, one entry per vertex)
  logic signed [26:0] exp_q[$];

  int in_count;
  int out_count;
  int mismatch_count;

  `uvm_component_utils(vn_shade_scoreboard)

  function new(string name, uvm_component parent);
    super.new(name, parent);
    in_export  = new("in_export", this);
    out_export = new("out_export", this);
    light_locked = 0;
  endfunction

  // Frame-boundary reset: clears the light-locked flag, the in-progress
  // triplet, and the expected FIFO. Must only be called after the previous
  // stream has fully drained — pending entries or an incomplete triplet
  // mean a reset was issued mid-frame.
  virtual task reset_state();
    if (exp_q.size() > 0)
      `uvm_error("SCB_RST", $sformatf("reset_state() called with %0d pending expected entries (reset issued mid-frame?)", exp_q.size()))
    if (light_locked && normal_word_idx != 0)
      `uvm_error("SCB_RST", $sformatf("reset_state() called with an incomplete normal triplet (%0d of 3 words)", normal_word_idx))
    light_locked    = 0;
    light_word_idx  = 0;
    normal_word_idx = 0;
    exp_q.delete();
  endtask

  virtual function void write_in(pipe_item item);
    logic signed [26:0] val;
    val = signed'(item.data[26:0]);
    in_count++;

    if (!light_locked) begin
      // Light preamble: first 4 input words per frame (Lx, Ly, Lz, + 1 hardware padding word)
      case (light_word_idx)
        0: Lx = val;
        1: Ly = val;
        2: Lz = val;
        3: begin
          light_locked = 1;
          `uvm_info("SCB_LIGHT", $sformatf("Light locked: Lx=%0d, Ly=%0d, Lz=%0d (plus 1 padding word)", Lx, Ly, Lz), UVM_MEDIUM)
        end
      endcase
      light_word_idx++;
    end else begin
      // Per-vertex loop: 3 input words per normal (nx, ny, nz), one accepted
      // cycle each. The three words are generally different — no identity
      // check.
      normal_word[normal_word_idx] = val;
      normal_word_idx++;
      if (normal_word_idx == 3) begin
        logic signed [63:0] nx64, ny64, nz64, sum, shifted;
        logic signed [26:0] exp_val;
        nx64 = $signed(normal_word[0]);
        ny64 = $signed(normal_word[1]);
        nz64 = $signed(normal_word[2]);

        // Exact signed sum, then a single arithmetic shift, before
        // narrowing. Operands are sign-extended to 64 bits first so the
        // 27x27 products are computed at full width.
        sum = nx64 * $signed(Lx) + ny64 * $signed(Ly) + nz64 * $signed(Lz);
        shifted = sum >>> 14;
        exp_val = signed'(shifted[26:0]);
        exp_q.push_back(exp_val);

        `uvm_info("SCB_IN", $sformatf("Normal (%0d,%0d,%0d) -> exp=%0d",
                  normal_word[0], normal_word[1], normal_word[2], exp_val), UVM_HIGH)
        normal_word_idx = 0;
      end
    end
  endfunction

  virtual function void write_out(pipe_item item);
    logic signed [26:0] got_val, exp_val;

    out_count++;
    got_val = signed'(item.data[26:0]);

    if (exp_q.size() == 0) begin
      `uvm_error("SCB_OUT", $sformatf("Output #%0d: unexpected output (spurious leading value?): got=%0d | light=(%0d,%0d,%0d)",
                out_count, got_val, Lx, Ly, Lz))
      mismatch_count++;
      return;
    end

    exp_val = exp_q.pop_front();
    if (got_val !== exp_val) begin
      `uvm_error("SCB_OUT", $sformatf("Output #%0d mismatch: got=%0d | exp=%0d | light=(%0d,%0d,%0d)",
                out_count, got_val, exp_val, Lx, Ly, Lz))
      mismatch_count++;
    end else begin
      `uvm_info("SCB_OUT", $sformatf("Output #%0d match: %0d", out_count, got_val), UVM_HIGH)
    end
  endfunction

  function void check_phase(uvm_phase phase);
    if (exp_q.size() > 0)
      `uvm_error("SCB_CHECK", $sformatf("Undrained expected outputs: %0d entries remain", exp_q.size()))
    if (light_locked && normal_word_idx != 0)
      `uvm_error("SCB_CHECK", $sformatf("Incomplete normal triplet at end of test: %0d of 3 words", normal_word_idx))
  endfunction

  function void report_phase(uvm_phase phase);
    `uvm_info("SCB_REPORT", $sformatf("=== VN_SHADE Scoreboard Summary ===\n  Inputs processed : %0d\n  Outputs captured : %0d\n  Mismatches       : %0d\n==================================",
              in_count, out_count, mismatch_count), UVM_LOW)
  endfunction

endclass

`endif
