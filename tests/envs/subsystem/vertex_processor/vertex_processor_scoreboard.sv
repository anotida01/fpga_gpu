`ifndef VERTEX_PROCESSOR_SCOREBOARD_SV
`define VERTEX_PROCESSOR_SCOREBOARD_SV

`uvm_analysis_imp_decl(_in)
`uvm_analysis_imp_decl(_pos)
`uvm_analysis_imp_decl(_shade)

// Scoreboard for the vertex_processor subsystem.
//
// Parses the DMA input stream (intended protocol: 16 matrix words, 3 light
// words, 1 count word = N*7, then N groups of 4 position words + 3 normal
// words). For each vertex it computes the expected position (xform row sums,
// >>>14, 27-bit per component, then LPM w-normalization with floor/ceil
// semantics) and the expected shade (3-term dot >>> 14, 27-bit), and compares
// against the DUT's vertex_xyzw and shade_vn_o outputs in vertex order. The
// two output channels are compared independently (independent pipeline
// latencies, both in-order per vertex).
//
// ext_golden_mode: the test pushes cmodel goldens per vertex (in vertex
// order, before the frame is sent). The inline model is cross-checked
// against the pushed value, and scoring is done against the pushed value
// (the cmodel is the authority on the exact channels).

class vertex_processor_scoreboard extends uvm_scoreboard;

  uvm_analysis_imp_in    #(pipe_item, vertex_processor_scoreboard) in_export;
  uvm_analysis_imp_pos   #(pipe_item, vertex_processor_scoreboard) pos_export;
  uvm_analysis_imp_shade #(pipe_item, vertex_processor_scoreboard) shade_export;

  // ------------------------------------------------------------- input parsing
  typedef enum {S_MAT, S_LIGHT, S_COUNT, S_VERT} scb_state_e;
  scb_state_e  st = S_MAT;
  int unsigned wcnt = 0;        // word index within current group
  int unsigned vtx_idx = 0;     // vertex index within current frame
  int unsigned n_vertices = 0;  // count word value (N*7 vertex words)
  bit          frame_open = 0;

  int mat[16];
  int L[3];
  int pos_buf[4];
  int nrm_buf[3];

  // ------------------------------------------------ expected values (vertex order)
  int exp_pos_x[$];
  int exp_pos_y[$];
  int exp_pos_z[$];
  int exp_shade[$];

  // ------------------------------------------- external (cmodel) goldens, pushed
  bit ext_golden_mode = 0;
  int ext_pos_x[$];
  int ext_pos_y[$];
  int ext_pos_z[$];
  int ext_pos_w[$];
  int ext_shade[$];

  // ----------------------------------------------------------- result counters
  int unsigned pos_checked = 0, pos_ok = 0, pos_err = 0;
  int unsigned shade_checked = 0, shade_ok = 0, shade_err = 0;

  `uvm_component_utils(vertex_processor_scoreboard)

  function new(string name, uvm_component parent);
    super.new(name, parent);
    in_export    = new("in_export", this);
    pos_export   = new("pos_export", this);
    shade_export = new("shade_export", this);
  endfunction

  // Push one cmodel golden vertex (vertex order, before the frame is sent).
  function void push_ext_golden(input int x, input int y, input int z, input int w, input int shade);
    ext_pos_x.push_back(x);
    ext_pos_y.push_back(y);
    ext_pos_z.push_back(z);
    ext_pos_w.push_back(w);
    ext_shade.push_back(shade);
  endfunction

  // Reset all parse/score state (call at the start of each frame).
  function void reset_state();
    st = S_MAT;
    wcnt = 0;
    vtx_idx = 0;
    n_vertices = 0;
    frame_open = 0;
    exp_pos_x.delete();
    exp_pos_y.delete();
    exp_pos_z.delete();
    exp_shade.delete();
    ext_pos_x.delete();
    ext_pos_y.delete();
    ext_pos_z.delete();
    ext_pos_w.delete();
    ext_shade.delete();
  endfunction

  // -------------------------------------------------------------- inline model

  // One xform row: sum of 4 int64 products, arithmetic shift >>> 14
  // (result is the low 27 bits, 2's complement).
  function automatic int xform_row_sum(input int m0, input int m1, input int m2, input int m3, input int v[4]);
    longint s;
    s = longint'(m0)*v[0] + longint'(m1)*v[1] + longint'(m2)*v[2] + longint'(m3)*v[3];
    return int'(s >>> 14);
  endfunction

  // LPM w-normalization semantics: n = v*2^14; w > 0: floor(n/w);
  // w < 0: ceil(n/w). (LPM divider truncates toward zero; the RTL adds the
  // floor/ceil correction based on the remainder and operand signs.)
  function automatic int w_norm_div(input int v, input int w);
    longint n, q0, r;
    int q;
    n = longint'(v) * 16384;
    q0 = n / w;
    r = n - q0 * w;
    q = int'(q0);
    if (r != 0) begin
      if (w > 0 && n < 0) q = q - 1;      // floor
      else if (w < 0 && n < 0) q = q + 1; // ceil
    end
    return q;
  endfunction

  // Shade: 3-term int64 dot product, arithmetic shift >>> 14 (27-bit result).
  function automatic int shade_dot(input int L[3], input int n[3]);
    longint s;
    s = longint'(L[0])*n[0] + longint'(L[1])*n[1] + longint'(L[2])*n[2];
    return int'(s >>> 14);
  endfunction

  // ------------------------------------------------------- expected value build

  protected function void complete_vertex();
    int v[4];
    int px, py, pz, pw, sh;
    int ex, ey, ez, ew, es;

    if (vtx_idx * 7 + 7 > n_vertices)
      `uvm_error("SCB", $sformatf("vertex words beyond count: vertex %0d of %0d", vtx_idx, n_vertices / 7))

    foreach (v[i]) v[i] = pos_buf[i];
    px = xform_row_sum(mat[0],  mat[1],  mat[2],  mat[3],  v);
    py = xform_row_sum(mat[4],  mat[5],  mat[6],  mat[7],  v);
    pz = xform_row_sum(mat[8],  mat[9],  mat[10], mat[11], v);
    pw = xform_row_sum(mat[12], mat[13], mat[14], mat[15], v);

    if (pw == 0)
      `uvm_error("SCB", $sformatf("vertex %0d: w == 0 (w_norm undefined); stimulus constraint violated", vtx_idx))
    else begin
      // LPM w-normalization (the v_xform stage after the row sums): the
      // v_fifo output is (x',y',z',16384) with x' = floor/ceil(x*2^14/w).
      px = w_norm_div(px, pw);
      py = w_norm_div(py, pw);
      pz = w_norm_div(pz, pw);
      pw = 16384;
    end

    sh = shade_dot(L, nrm_buf);

    if (ext_golden_mode) begin
      if (ext_pos_x.size() == 0) begin
        `uvm_error("SCB", $sformatf("vertex %0d: no external golden pushed", vtx_idx))
      end
      else begin
        ex = ext_pos_x.pop_front();
        ey = ext_pos_y.pop_front();
        ez = ext_pos_z.pop_front();
        ew = ext_pos_w.pop_front();
        es = ext_shade.pop_front();
        if (ex != px || ey != py || ez != pz || ew != 16384 || es != sh)
          `uvm_error("SCB", $sformatf("vertex %0d: inline model disagrees with pushed golden: pos inline (%0d,%0d,%0d,w=%0d) vs pushed (%0d,%0d,%0d,w=%0d); shade inline %0d vs pushed %0d — scoring against pushed (cmodel is authority)", vtx_idx, px, py, pz, pw, ex, ey, ez, ew, sh, es))
        px = ex;
        py = ey;
        pz = ez;
        sh = es;
      end
    end

    exp_pos_x.push_back(px);
    exp_pos_y.push_back(py);
    exp_pos_z.push_back(pz);
    exp_shade.push_back(sh);
    vtx_idx++;

    if (vtx_idx * 7 == n_vertices) begin
      // Frame complete
      st = S_MAT;
      frame_open = 0;
      if (ext_pos_x.size() != 0)
        `uvm_error("SCB", $sformatf("%0d pushed goldens remain after frame end", ext_pos_x.size()))
    end
  endfunction

  // --------------------------------------------------------- analysis writes

  virtual function void write_in(pipe_item item);
    int w;
    w = $signed(item.data[31:0]);
    case (st)
      S_MAT: begin
        mat[wcnt] = w;
        wcnt++;
        if (wcnt == 16) begin
          wcnt = 0;
          st = S_LIGHT;
        end
      end
      S_LIGHT: begin
        L[wcnt] = w;
        wcnt++;
        if (wcnt == 3) begin
          wcnt = 0;
          st = S_COUNT;
        end
      end
      S_COUNT: begin
        n_vertices = w;
        vtx_idx = 0;
        wcnt = 0;
        if (n_vertices % 7 != 0)
          `uvm_error("SCB", $sformatf("vertex count %0d is not a multiple of 7", n_vertices))
        if (n_vertices == 0) begin
          frame_open = 0;
          st = S_MAT;
        end
        else begin
          frame_open = 1;
          st = S_VERT;
        end
      end
      S_VERT: begin
        if (wcnt < 4)
          pos_buf[wcnt] = w;
        else
          nrm_buf[wcnt - 4] = w;
        wcnt++;
        if (wcnt == 7) begin
          wcnt = 0;
          complete_vertex();
        end
      end
    endcase
  endfunction

  virtual function void write_pos(pipe_item item);
    bit [107:0] d;
    int x, y, z, w;
    int ex, ey, ez;

    d = item.data[107:0];
    x = $signed(d[107:81]);
    y = $signed(d[80:54]);
    z = $signed(d[53:27]);
    w = $signed(d[26:0]);

    if (exp_pos_x.size() == 0) begin
      `uvm_error("SCB", "pos output received with no expected value (DUT produced an extra vertex)")
      return;
    end

    ex = exp_pos_x.pop_front();
    ey = exp_pos_y.pop_front();
    ez = exp_pos_z.pop_front();
    pos_checked++;

    if (w != 16384)
      `uvm_error("SCB", $sformatf("pos[%0d]: w = %0d, expected 16384", pos_checked, w))
    if (x != ex || y != ey || z != ez) begin
      pos_err++;
      `uvm_error("SCB", $sformatf("pos[%0d] mismatch: got (%0d,%0d,%0d,w=%0d) expected (%0d,%0d,%0d,w=16384)", pos_checked, x, y, z, w, ex, ey, ez))
    end
    else begin
      pos_ok++;
    end
  endfunction

  virtual function void write_shade(pipe_item item);
    int s, es;

    s = $signed(item.data[26:0]);

    if (exp_shade.size() == 0) begin
      `uvm_error("SCB", "shade output received with no expected value (DUT produced an extra vertex)")
      return;
    end

    es = exp_shade.pop_front();
    shade_checked++;
    if (s != es) begin
      shade_err++;
      `uvm_error("SCB", $sformatf("shade[%0d] mismatch: got %0d expected %0d", shade_checked, s, es))
    end
    else begin
      shade_ok++;
    end
  endfunction

  // --------------------------------------------------------------- phases

  function void check_phase(uvm_phase phase);
    super.check_phase(phase);
    if (frame_open)
      `uvm_error("SCB", "frame was still open at end of test (incomplete vertex words)")
    if (exp_pos_x.size() != 0)
      `uvm_error("SCB", $sformatf("%0d expected pos outputs never observed", exp_pos_x.size()))
    if (exp_shade.size() != 0)
      `uvm_error("SCB", $sformatf("%0d expected shade outputs never observed", exp_shade.size()))
  endfunction

  function void report_phase(uvm_phase phase);
    super.report_phase(phase);
    `uvm_info("SCB", $sformatf("Scoreboard totals: pos %0d checked (%0d ok, %0d err); shade %0d checked (%0d ok, %0d err)", pos_checked, pos_ok, pos_err, shade_checked, shade_ok, shade_err), UVM_LOW)
  endfunction

endclass

`endif
