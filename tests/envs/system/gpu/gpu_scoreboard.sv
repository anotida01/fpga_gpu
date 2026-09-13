`ifndef GPU_SCOREBOARD_SV
`define GPU_SCOREBOARD_SV

// System-level scoreboard for env_gpu. It observes the single host AXI4-Lite
// stream (the s00 CPU port of axil_sys_top) and routes each transaction to the
// reference model selected by the host-bus address map:
//   - control region (0x0100_0000-0x01FF_FFFF) -> the 5-register model below,
//     mirroring the axfe unit scoreboard's proven register semantics.
//   - RAM region     (0x0000_0000-0x00FF_FFFF)  -> the shared axi4lite_mem_model
//     (reference model of the DUT-internal axil_ram0, as seen from the host).
// This keeps the scoreboard forward-compatible with the future mesh-seeding and
// c_model golden-framebuffer tests (which will exercise the RAM region) without
// the write-read smoke test needing to touch it.
class gpu_scoreboard extends uvm_scoreboard;
  `uvm_analysis_imp_decl(_host)
  uvm_analysis_imp_host #(axi4lite_seq_item, gpu_scoreboard) host_export;

  axi4lite_mem_model mem_model; // reference for the RAM region (set by env)
  virtual irq_if irq_vif;       // DUT's GPU done/irq line (dut.gpu0.irq_gpu), live DUT truth

  // --- Control register model (identical semantics to the axfe unit env) -------
  // The control reg file is axil_control.sv (register bits at 354-358):
  //   reg0 CONTROL   [0]=start(self-clear after a frame), [1]=reset-req  (R/W)
  //   reg1 STATUS    [0]=gpu_done (LIVE mirror of intr_gen.irq_o)          (R)
  //   reg2 INT_CLR   [0]=clr_gpu_done (W1C, self-clears on nonzero write)
  //   reg3 IN_MEM_OFF  base offset for DMA input reads                    (R/W)
  //   reg4 OUT_MEM_OFF base offset for framebuffer writes                 (R/W)
  typedef struct {
    bit          is_live; // 1 => readback DUT-driven; CPU writes dropped
    logic [31:0] wmask;   // effective write mask
    logic [31:0] stored;  // regfile contents (== interrupt state for the live reg)
  } reg_model_t;
  localparam int NUM_REGS = 5;
  reg_model_t rm[NUM_REGS];

  // AXI4-Lite response codes (2'b00 = OKAY): a valid in-range access must complete OKAY.
  localparam logic [1:0] RESP_OKAY = 2'b00;

  // Region decode on the host bus (see gpu_env_pkg address-map constants).
  function bit in_ram_region (input logic [31:0] addr);
    return (addr < GPU_CTRL_BASE);
  endfunction
  function bit in_ctrl_region(input logic [31:0] addr);
    return (addr >= GPU_CTRL_BASE) && (addr < (GPU_CTRL_BASE + 32'h0100_0000));
  endfunction
  // Control word index from the full host address.
  function int reg_index(input logic [31:0] addr);
    return ((addr - GPU_CTRL_BASE) >> 2);
  endfunction

  int ctrl_write_count = 0;
  int ctrl_check_count = 0;
  int ram_write_count  = 0; // host-bus RAM writes (e.g. mesh seeding)
  int ram_check_count  = 0; // host-bus RAM reads (total)
  int ram_unseeded     = 0; // RAM reads reported-only (GPU-written / not bus-seeded)
  int oob_count        = 0;
  int expected_ctrl_rd = -1; // -1 = unspecified, otherwise enforce exact count
  int expected_ctrl_wr = -1; // -1 = unspecified, otherwise enforce exact count

  // --- C-model golden framebuffer sink (opt-in) --------------------------------
  // Off by default so the existing ctrl smoke / sys_access / multi_frame tests
  // (which never set this) keep their exact current report_phase output. A test
  // publishes it via uvm_config_db#(bit) to enable the DPI-C golden path:
  // cmodel_run(memh), then a per-pixel compare of the DUT readback against
  // cmodel_fb_pixel (16-bit RGB565 grey). The C-model is the reference: any
  // out-of-tolerance pixel is treated as a candidate DUT defect.
  bit          enable_cmodel_golden = 0; // knob, read in build_phase
  bit          golden_checked  = 0;      // a golden run was attempted this test
  bit          golden_pass     = 1;      // cleared on any per-pixel/C error
  int unsigned golden_mismatch = 0;      // aggregate per-pixel mismatch count
  int          golden_first_x  = -1;     // first mismatched pixel (x,y)
  int          golden_first_y  = -1;
  int unsigned golden_rc_err   = 0;      // cmodel_run() non-OK code (link/path)
  localparam int GOLDEN_W = 320;         // ROP_BUF_WIDTH (gpu_base_test.sv)
  localparam int GOLDEN_H = 240;         // ROP_BUF_HEIGHT

  `uvm_component_utils(gpu_scoreboard)

  function new(string name, uvm_component parent);
    super.new(name, parent);
    host_export = new("host_export", this);
    model_reset();
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    // Fetch the DUT's GPU done/irq probe (tb drives it from dut.gpu0.irq_gpu).
    // STATUS (reg1) bit0 is *live* DUT state; preferred as the scoreboard model
    // as soon as this virtual-if is available.
    if (!uvm_config_db#(virtual irq_if)::get(this, "", "irq_vif", irq_vif))
      `uvm_warning("SCB_IRQ", "irq_vif not published; STATUS(reg1) will use the stored reg model")
    // C-model golden sink is strictly opt-in; tests that keep the knob at its
    // default of 0 see no DPI-C calls and no report_phase change.
    uvm_config_db#(bit)::get(this, "", "enable_cmodel_golden", enable_cmodel_golden);
    `uvm_info("SCB_GOLDEN", $sformatf("enable_cmodel_golden=%0b", enable_cmodel_golden), UVM_MEDIUM)
  endfunction

  // --- Register-model event hooks (fallback when irq_vif is not provided) -----
  function void model_reset();
    for (int i = 0; i < NUM_REGS; i++) begin
      rm[i].is_live = (i == 1);
      rm[i].wmask   = (i == 1) ? 32'h1 : 32'hFFFFFFFF;
      rm[i].stored  = 32'h0;
    end
  endfunction

  // Retained for API parity with the axfe unit env; the system scoreboard now
  // prefers the live irq probe (irq_vif.irq) as the STATUS model, so these only
  // matter if irq_vif was not published.
  function void report_gpu_done();
    rm[1].stored = 32'h1; // STATUS[0] reflects the latched gpu_done interrupt
  endfunction

  function void clear_gpu_done();
    rm[1].stored = 32'h0; // INT_CLR W1C deasserts intr_gen.irq_o
  endfunction

  // Expected readback of control word `idx`.
  // STATUS (reg1) bit0 is *live* DUT state: prefer the tb-probe irq_vif.irq
  // (dut.gpu0.irq_gpu) as the authoritative model, falling back to the stored
  // reg model when no probe was published. This keeps STATUS readback checks
  // in step with the DUT by construction -- no stale-model mismatch, and no
  // host-bus STATUS polling needed by the tests.
  function logic [31:0] expected_readback(int idx);
    if (idx < 0 || idx >= NUM_REGS) return 32'h0;
    if (rm[idx].is_live) begin
      if (irq_vif != null) return {31'h0, irq_vif.irq};
      return {31'h0, rm[idx].stored[0]};
    end
    return rm[idx].stored;
  endfunction

  // --- Single host-stream entry: route by address region -----------------------
  virtual function void write_host(axi4lite_seq_item item);
    if (in_ctrl_region(item.addr))      handle_ctrl(item);
    else if (in_ram_region(item.addr))  handle_ram(item);
    else begin
      oob_count++;
      `uvm_info("SCB_OOB", $sformatf("Access to out-of-range addr 0x%0h (op=%s) observed resp=%b",
                  item.addr, (item.op==WRITE)?"W":"R", item.resp), UVM_MEDIUM)
    end
  endfunction

  // Control-register write/read model (same contract as the axfe unit scoreboard).
  virtual function void handle_ctrl(axi4lite_seq_item item);
    int idx = reg_index(item.addr);
    if (item.op == WRITE) begin
      ctrl_write_count++;
      if (idx >= NUM_REGS) begin
        `uvm_info("SCB_CTRL", $sformatf("Write to out-of-range ctrl offset 0x%0h dropped", item.addr), UVM_MEDIUM)
        return;
      end
      if (item.resp !== RESP_OKAY)
        `uvm_error("SCB_CTRL", $sformatf("Write to Reg[%0d] at 0x%0h returned resp=%b, expected OKAY=%b",
                    idx, item.addr, item.resp, RESP_OKAY))
      if (rm[idx].is_live) begin
        `uvm_info("SCB_CTRL", $sformatf("Write to live Reg[%0d] dropped; stored=%b", idx, rm[idx].stored), UVM_MEDIUM)
        return;
      end
      for (int b = 0; b < 4; b++)
        if (item.strb[b]) rm[idx].stored[b*8 +: 8] = item.data[b*8 +: 8];
      rm[idx].stored = rm[idx].stored & rm[idx].wmask;
      `uvm_info("SCB_CTRL", $sformatf("Write Reg[%0d] = %h (mask %h)", idx, rm[idx].stored, rm[idx].wmask), UVM_MEDIUM)
       if (idx == 2) begin // INT_CLR: W1C. We do NOT model STATUS clearing here;
         // the live irq probe (irq_vif.irq) is the authoritative STATUS model once
         // the DUT's irq_gpu deasserts after intr_gen leaves the HOLD state.
         // We only model the stored INT_CLR register's own self-clear (reg2 -> 0).
         rm[idx].stored = 32'h0;
       end
    end else begin
      logic [31:0] expected;
      if (idx >= NUM_REGS) begin
        `uvm_info("SCB_CTRL", $sformatf("Read of out-of-range ctrl offset 0x%0h observed resp=%b", item.addr, item.resp), UVM_MEDIUM)
        return;
      end
      ctrl_check_count++;
      expected = expected_readback(idx);
      if (item.resp !== RESP_OKAY)
        `uvm_error("SCB_CTRL", $sformatf("Read Reg[%0d] at 0x%0h returned resp=%b, expected OKAY=%b",
                    idx, item.addr, item.resp, RESP_OKAY))
      if (item.data !== expected)
        `uvm_error("SCB_CTRL", $sformatf("Mismatch at ctrl Reg[%0d] (0x%0h): Exp %h, Got %h",
                    idx, item.addr, expected, item.data))
      else
        `uvm_info("SCB_CTRL", $sformatf("Match at ctrl Reg[%0d] (0x%0h): %h", idx, item.addr, item.data), UVM_HIGH)
    end
  endfunction

  // RAM-region (DUT-internal axil_ram0) model. Writes are tracked in the shared
  // mem model; reads are checked against it ONLY if the word was seeded via the
  // bus (present in the mem model). Out-of-band seeds (e.g. $readmemh into the
  // DUT RAM for render tests) are therefore reported, not falsely failed.
  virtual function void handle_ram(axi4lite_seq_item item);
    if (item.op == WRITE) begin
      ram_write_count++;
      mem_model.write(item.addr, item.data);
      if (item.resp !== RESP_OKAY)
        `uvm_error("SCB_RAM", $sformatf("RAM write to 0x%0h returned resp=%b, expected OKAY=%b",
                    item.addr, item.resp, RESP_OKAY))
      // Per-write trace suppressed (UVM_HIGH): a render seeds 272 words / reads tens
      // of thousands; the counts are summarised in report_phase instead.
      `uvm_info("SCB_RAM", $sformatf("RAM Write 0x%0h = %h", item.addr, item.data), UVM_HIGH)
    end else begin
      ram_check_count++;
      if (item.resp !== RESP_OKAY)
        `uvm_error("SCB_RAM", $sformatf("RAM read at 0x%0h returned resp=%b, expected OKAY=%b",
                    item.addr, item.resp, RESP_OKAY))
      if (mem_model.mem.exists(item.addr)) begin
        if (item.data !== mem_model.read(item.addr))
          `uvm_error("SCB_RAM", $sformatf("RAM Mismatch at 0x%0h: Exp %h, Got %h",
                      item.addr, mem_model.read(item.addr), item.data))
        else
          `uvm_info("SCB_RAM", $sformatf("RAM Match at 0x%0h: %h", item.addr, item.data), UVM_HIGH)
      end else begin
        ram_unseeded++;
        // GPU-written (unseeded) word: reported-only at UVM_HIGH (not a failure);
        // aggregate count surfaces in the report_phase summary.
        `uvm_info("SCB_RAM", $sformatf("RAM read at 0x%0h (unseeded, reported only): %h", item.addr, item.data), UVM_HIGH)
      end
    end
  endfunction

  // --- C-model golden framebuffer sink ------------------------------------------
  // Renders the given mesh in the C-model golden reference and compares the
  // DUT readback (dut_fb[], one 32-bit word per pixel, row-major indexed
  // [y*GOLDEN_W + x], as produced by the test's bus readback in the same shape
  // as tc_gpu_multi_frame.sv:61-65) pixel-by-pixel against cmodel_fb_pixel()
  // (16-bit RGB565 grey word).
  //
    // The C-model is the reference: a pixel beyond the colour-contract tolerance
    // (|L_dut - L_cm| > 1, or not RGB565 grey {L, {L, L[4]}, L}) is a candidate
    // DUT defect. We UVM_ERROR it and capture the DUT value in the message. We
    // never relax the tolerance to force a pass.
  //
  // No-op (UVM_INFO + return) when enable_cmodel_golden is 0, so the existing
  // tests are untouched. Must be called from a task context (it calls the
  // DPI-C cmodel_run, which is a task in the DPI sense; safe in run_phase).
  virtual task check_framebuffer_golden(input string memh,
                                        input logic [31:0] dut_fb[]);
    int unsigned rc, expected;
    logic [15:0] dut16;
    logic [4:0]  r_dut, r_exp;
    logic [5:0]  g_dut, b_dut;
    int unsigned mismatch;
    int          x, y;
    int          reported;

    golden_checked  = 1;
    golden_pass     = 1;
    golden_mismatch = 0;
    golden_first_x  = -1;
    golden_first_y  = -1;
    golden_rc_err   = 0;

    if (!enable_cmodel_golden) begin
      `uvm_info("SCB_GOLDEN", "enable_cmodel_golden=0; golden framebuffer check skipped", UVM_MEDIUM)
      return;
    end

    // DPI-C link gate: the shared library must actually have resolved before we
    // trust any cmodel_* result (cmodel_version() == ABI major 1).
    if (!gpu_cmodel_pkg::cmodel_version_ok()) begin
      `uvm_fatal("SCB_GOLDEN", "cmodel_version_ok()=0; DPI-C link did not resolve")
    end

    // (a) Render the golden once. A non-OK code means the C model never
    // rendered -- almost always a mesh path/CWD resolution issue or a link/state
    // problem; report and stop (there is no valid golden to compare).
    rc = gpu_cmodel_pkg::cmodel_run(memh);
    if (rc != CMODEL_OK) begin
      golden_pass   = 0;
      golden_rc_err = rc;
      `uvm_error("SCB_GOLDEN", $sformatf(
                 "cmodel_run(%0s) returned error %0h (CMODEL_FILE_ERROR=%0h); no golden rendered -- check mesh path under xrun CWD",
                 memh, rc, CMODEL_FILE_ERROR))
      return;
    end

    // (b) Per-pixel colour-contract compare. 76800 single-pixel DPI calls -- no
    // batch read is exposed by the C-model in this build.
    mismatch = 0;
    reported = 0;
    for (y = 0; y < GOLDEN_H; y++) begin
      for (x = 0; x < GOLDEN_W; x++) begin
        expected = gpu_cmodel_pkg::cmodel_fb_pixel(x, y); // 16-bit RGB565 word
        dut16    = dut_fb[y*GOLDEN_W + x][15:0];          // only [15:0] matters (contract)
        r_dut    = dut16[15:11];                          // 5-bit Red  = intensity L
        g_dut    = dut16[10:5];                           // 6-bit Green (MSB-replicated L)
        b_dut    = dut16[4:0];                            // 5-bit Blue
        r_exp    = expected[15:11];
        // Contract: RGB565 grey {L, {L, L[4]}, L}, |L_dut - L_exp| <= 1.
        begin
          bit fail = 1'b0;
          if ((r_dut != b_dut) || (g_dut != {r_dut, r_dut[4]}))
            fail = 1'b1; // non-RGB565-grey pattern / bad MSB replication
          if (((r_dut >= r_exp) ? (r_dut - r_exp) : (r_exp - r_dut)) > 5'd1)
            fail = 1'b1; // beyond 1-LSB intensity tolerance
          if (fail) begin
            mismatch = mismatch + 1;
            if (golden_first_x < 0) begin
              golden_first_x = x;
              golden_first_y = y;
            end
            if (reported < 5) begin
              `uvm_error("SCB_GOLDEN", $sformatf(
                         "GOLDEN MISMATCH at (%0d,%0d): Exp %h, Got %h (L exp=%0d got=%0d)",
                         x, y, expected, dut16, r_exp, r_dut))
              reported = reported + 1;
            end
          end
        end
      end
    end

    if (mismatch > 0) begin
      golden_pass = 0;
      `uvm_error("SCB_GOLDEN", $sformatf(
                 "%0d pixel(s) beyond colour-contract tolerance (first at (%0d,%0d))",
                 mismatch, golden_first_x, golden_first_y))
    end
    golden_mismatch = mismatch;
  endtask

  function void check_phase(uvm_phase phase);
    if (expected_ctrl_rd >= 0 && ctrl_check_count != expected_ctrl_rd)
      `uvm_error("SCB_CHECK", $sformatf("Expected %0d ctrl read checks, got %0d", expected_ctrl_rd, ctrl_check_count))
    if (expected_ctrl_wr >= 0 && ctrl_write_count != expected_ctrl_wr)
      `uvm_error("SCB_CHECK", $sformatf("Expected %0d ctrl writes, got %0d", expected_ctrl_wr, ctrl_write_count))
  endfunction

  function void report_phase(uvm_phase phase);
    `uvm_info("SCB_REPORT", $sformatf(
      "=== Summary: CTRL Writes: %0d, CTRL Read-Checks: %0d, OOR: %0d | RAM Writes: %0d, RAM Reads: %0d (unseeded/reported-only: %0d) ===",
      ctrl_write_count, ctrl_check_count, oob_count,
      ram_write_count, ram_check_count, ram_unseeded), UVM_LOW)
    // Golden summary: printed only when a golden run happened this
    // test, so the existing tests (knob off) keep their exact output.
    if (golden_checked) begin
      if (golden_pass)
        `uvm_info("SCB_REPORT", $sformatf(
          "=== GOLDEN: PASS (0 mismatches, %0d words) ===", GOLDEN_W*GOLDEN_H), UVM_LOW)
      else if (golden_rc_err != 0)
        `uvm_error("SCB_REPORT", $sformatf(
          "=== GOLDEN: FAIL (C-model render error %0h; 0 pixels compared) ===", golden_rc_err))
      else
        `uvm_error("SCB_REPORT", $sformatf(
          "=== GOLDEN: FAIL (%0d mismatches, first at (%0d,%0d)) ===",
          golden_mismatch, golden_first_x, golden_first_y))
    end
  endfunction

endclass

`endif
