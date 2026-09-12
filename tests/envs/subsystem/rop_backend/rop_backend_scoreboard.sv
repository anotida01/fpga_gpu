`ifndef ROP_BACKEND_SCOREBOARD_SV
`define ROP_BACKEND_SCOREBOARD_SV

// Scoreboard for the axil_rop_backend subsystem env.
//
// Reference (intended behavior, C-model-free inline math):
//  - Input pixels (x_i, y_i, c_i) arrive on the pipe monitor; the scoreboard
//    computes the golden AXI4-Lite write exactly as the DE1-SoC pixel buffer
//    requires (board manual sec 4.2.1, Figure 19):
//      * fixed-point coordinates (14 fractional bits): px = round(x_i / 2^14),
//        py = round(y_i / 2^14)  (i.e. (x_i + 2^13) >>> 14)
//      * grey intensity: c5     = ((c_i * 32'sd32768) >>> 28)[4:0]  (0 if c_i < 0)
//                         color16 = {c5, c5, 1'b0, c5}             (16-bit RGB 5-6-5)
//      * address: byte offset = {py[7:0], px[8:0], 1'b0} = 1024*py + 2*px
//                          (row pitch 1024 B; ref points (1,0)->+0x02, (0,1)->+0x400)
//      * half-word placement: even px -> low 16 bits + wstrb 4'b0011,
//                             odd  px -> high 16 bits + wstrb 4'b1100
//      * output_mem_offset_addr is added in byte units on top of the offset.
//  - Every accepted pixel must produce exactly one AXI4-Lite WRITE (the DUT is
//    a write-only master; a READ or a missing/duplicated WRITE is an error).

class rop_backend_scoreboard extends uvm_scoreboard;
  `uvm_analysis_imp_decl(_in)
  `uvm_analysis_imp_decl(_axi)

  uvm_analysis_imp_in  #(pipe_item, rop_backend_scoreboard)             in_export;
  uvm_analysis_imp_axi #(axi4lite_seq_item, rop_backend_scoreboard)    axi_export;

  // Framebuffer geometry (DE1-SoC pixel buffer, board manual sec 4.2.1):
  // byte offset = 1024*py + 2*px, py is 8 bits, px is 9 bits per the fixed
  // address format. In-range pixels (px < 320, py < 240) are unaffected by the
  // field widths.
  localparam logic [7:0] FB_PITCH = 1024; // bytes per row

  // Byte address base the DUT adds to every pixel offset (mirrors the test's
  // +MEM_OFFSET plusarg / tb's output_mem_offset_addr_i binding).
  logic [31:0] mem_offset = 32'h0;

  typedef struct packed {
    logic [31:0] addr;
    logic [31:0] data;
    logic [3:0]  strb;
  } expected_tx_t;

  expected_tx_t exp_q[$];

  int unsigned in_count      = 0;
  int unsigned out_count     = 0;
  int unsigned mismatch_cnt  = 0;

  `uvm_component_utils(rop_backend_scoreboard)

  function new(string name, uvm_component parent);
    super.new(name, parent);
    in_export  = new("in_export",  this);
    axi_export = new("axi_export", this);
  endfunction

  // --- Golden write computation for one input pixel ---------------------------
  local function expected_tx_t compute_expected(logic [31:0] x_i,
                                                logic [31:0] y_i,
                                                logic signed [31:0] c_i);
    expected_tx_t tx;
    logic [31:0] px, py;
    logic [4:0]  c5;
    logic [15:0] color16;

    // Coordinate normalization: round(x_i / 2^14), as (x_i + 2^13) >>> 14.
    px = (x_i + (32'd1 << 13)) >>> 14;
    py = (y_i + (32'd1 << 13)) >>> 14;

    // Grey intensity to 5 bits: (c_i * 0x07C000) >>> 28, low 5 bits; clamp
    // negative intensities to 0. The 16-bit RGB 5-6-5 pixel is grey
    // {c5(R), c5(G low 5), 1'b0(G MSB), c5(B)}.
    c5 = (c_i < 32'sd0) ? 5'd0
                        : ((64'(c_i) * 64'sd32768) >>> 28) & 5'h1F;
    color16 = {c5, c5, 1'b0, c5};

    // Pixel half-word placement + DE1-SoC pixel buffer byte offset.
    if (px[0]) begin
      tx.data = {color16, 16'h0};
      tx.strb = 4'b1100;
    end else begin
      tx.data = {16'h0, color16};
      tx.strb = 4'b0011;
    end
    tx.addr = mem_offset + (32'(py[7:0]) << 10) + (32'(px[8:0]) << 1);
    return tx;
  endfunction

  virtual function void write_in(pipe_item item);
    logic [31:0]        x_i;
    logic signed [31:0] c_i;
    logic [31:0]        y_i;
    expected_tx_t       tx;

    x_i = item.data[31:0];
    c_i = signed'(item.data[63:32]);
    y_i = item.data[95:64];

    tx = compute_expected(x_i, y_i, c_i);
    exp_q.push_back(tx);
    in_count++;
    `uvm_info("SCB_IN", $sformatf(
      "In tx %0d: x_i=%0d (c=%0d) y_i=%0d -> exp addr=0x%0h data=0x%0h strb=%b",
      in_count, x_i, c_i, y_i, tx.addr, tx.data, tx.strb), UVM_MEDIUM)
  endfunction

  virtual function void write_axi(axi4lite_seq_item item);
    expected_tx_t exp;

    out_count++;
    if (item.op != WRITE) begin
      mismatch_cnt++;
      `uvm_error("SCB_AXI", $sformatf(
        "Unexpected READ on the DUT write-only AXI port (addr=0x%0h) -- the ROP backend must not issue reads",
        item.addr))
      return;
    end
    if (item.resp != 2'b00) begin
      mismatch_cnt++;
      `uvm_error("SCB_AXI", $sformatf(
        "WRITE at addr=0x%0h completed with bresp=%b (expected OKAY 2'b00)",
        item.addr, item.resp))
    end
    if (exp_q.size() == 0) begin
      mismatch_cnt++;
      `uvm_error("SCB_AXI", $sformatf(
        "Unexpected WRITE with no queued expected pixel (addr=0x%0h data=0x%0h strb=%b)",
        item.addr, item.data, item.strb))
      return;
    end
    exp = exp_q.pop_front();
    if (item.addr !== exp.addr || item.data !== exp.data || item.strb !== exp.strb) begin
      mismatch_cnt++;
      `uvm_error("SCB_AXI", $sformatf(
        "Mismatch @%0d: got  addr=0x%0h data=0x%0h strb=%b | exp addr=0x%0h data=0x%0h strb=%b",
        out_count, item.addr, item.data, item.strb,
                exp.addr, exp.data, exp.strb))
    end else begin
      `uvm_info("SCB_AXI", $sformatf("Match @%0d: addr=0x%0h data=0x%0h strb=%b",
                out_count, item.addr, item.data, item.strb), UVM_MEDIUM)
    end
  endfunction

  function void check_phase(uvm_phase phase);
    if (exp_q.size() > 0)
      `uvm_error("SCB_CHECK", $sformatf(
        "%0d expected frame-buffer write(s) never observed on the AXI port", exp_q.size()))
  endfunction

  function void report_phase(uvm_phase phase);
    `uvm_info("SCB_REPORT", $sformatf(
      "=== ROP Backend Scoreboard Summary ===\n  Pixels accepted  : %0d\n  AXI writes seen  : %0d\n  Mismatches       : %0d\n==================================",
      in_count, out_count, mismatch_cnt), UVM_LOW)
  endfunction

endclass

`endif
