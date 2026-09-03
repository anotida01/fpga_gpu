`ifndef AXFE_SCOREBOARD_SV
`define AXFE_SCOREBOARD_SV

class axfe_scoreboard extends uvm_scoreboard;
  `uvm_analysis_imp_decl(_ctrl)
  `uvm_analysis_imp_decl(_dma_req)
  `uvm_analysis_imp_decl(_dma_rsp)

  uvm_analysis_imp_ctrl #(axi4lite_seq_item, axfe_scoreboard) ctrl_export;
  uvm_analysis_imp_dma_req #(pipe_item, axfe_scoreboard) dma_req_export;
  uvm_analysis_imp_dma_rsp #(pipe_item, axfe_scoreboard) dma_rsp_export;

  axi4lite_mem_model mem_model;

  // Per-register self-describing model. A register's readback semantics are
  // derived from axil_control.sv (writemask gen at 43-49, live mirror at
  // 395-396, W1C/self-clear at 399, reset at 383). A register is either:
  //   - stored : DUT keeps the written (masked) value in its regfile; readback == stored.
  //   - live   : DUT re-drives the value every cycle from live DUT state; CPU writes are
  //              dropped (readback never reflects a write). Reg1 (STATUS, offset 0x04)
  //              is the live mirror of the gpu_done interrupt (intr_gen.irq_o).
  typedef struct {
    bit          is_live;   // 1 => readback DUT-driven; writes dropped
    logic [31:0] wmask;     // effective write mask (axil_control.sv:43-49)
    logic [31:0] stored;    // regfile contents for stored regs; == interrupt state for live regs
  } reg_model_t;
  localparam int NUM_REGS = 5;
  reg_model_t rm[NUM_REGS];

  // AXI4-Lite response codes (AMBA AXI, 2'b00 is OKAY). A *valid* access to a
  // defined register must complete with OKAY; this is the gap item 1 closes.
  localparam logic [1:0] RESP_OKAY = 2'b00; // OKAY
  localparam logic [1:0] RESP_SLV  = 2'b01; // SLVERR (reference)
  localparam logic [1:0] RESP_DEC  = 2'b10; // DECERR (reference)

  // Derived: Reg3 is IN_MEM_OFF (axil_control.sv:356); the DMA base offset is
  // Reg3's stored value. Exposed as a getter so callers don't reach into rm[3].
  function logic [31:0] get_dma_input_offset();
    return rm[3].stored;
  endfunction

  int dma_req_count = 0;
  int dma_rsp_count = 0;
  int ctrl_check_count = 0;
  int ctrl_write_count = 0;
  int expected_ctrl_rd = -1; // -1 means default/unspecified, otherwise enforce exact count
  int expected_dma_rsp = -1; // -1 means default/unspecified, otherwise enforce exact count
  logic [31:0] exp_dma_addr_q[$];

  // Out-of-range (decode-miss) response contract, configurable so the scoreboard
  // captures the DUT's actual behavior by default rather than baking in a
  // protocol-legal-but-undecided choice. AXI4-Lite allows EITHER OKAY+read0 or
  // DECERR on a decode miss; which is *intended* is an open design decision
  // (WORK_axfe_design_decisions, W6). Until then we only report the observed
  // resp (en_oob_resp==0). After the decision, a test may set en_oob_resp=1
  // and oob_exp_resp=<decided code> to enforce it.
  bit          en_oob_resp  = 1'b0;  // 0 = report only (default), 1 = enforce exact resp
  logic [1:0]  oob_exp_resp = 2'b00; // expected OOR resp when en_oob_resp is set

  `uvm_component_utils(axfe_scoreboard)

  function new(string name, uvm_component parent);
    super.new(name, parent);
    ctrl_export    = new("ctrl_export", this);
    dma_req_export = new("dma_req_export", this);
    dma_rsp_export = new("dma_rsp_export", this);
    model_reset();
  endfunction

  // --- Register-model event hooks (item S2) ---------------------------------
  // These mirror the DUT's intr_gen at the *event* level rather than copying
  // its FSM. Callers fire them when the DUT's live STATUS bit (Reg1 bit0) changes,
  // so tests read like the RTL and do not carry DUT interrupt knowledge:
  //   model_reset()     : DUT reset           -> Reg1 stored <= 0 (intr_gen reset)
  //   report_gpu_done() : start->done latched -> Reg1 stored <= 1 (irq_o asserted)
  //   clear_gpu_done()  : INT_CLR W1C write   -> Reg1 stored <= 0 (irq_o deasserted)
  // Reg1 readback expectation is rm[1].stored (see expected_readback below).

  function void model_reset();
    for (int i = 0; i < NUM_REGS; i++) begin
      rm[i].is_live = (i == 1);
      rm[i].wmask   = (i == 1) ? 32'h1 : 32'hFFFFFFFF;
      rm[i].stored  = 32'h0;
    end
    // A hard reset drops any in-flight DMA read in the DUT (axil_dma_master:
    // reset -> state<=RESET, address_i_reg/dma_out<=0), so a req pushed by the
    // monitor before the reset has no post-reset response. Clear the pending
    // req queue so check_phase does not flag it as "unfinished". A GENUINE
    // post-reset DMA response is still caught: with the queue empty,
    // write_dma_rsp hits the `Unexpected DMA response` error branch below.
    exp_dma_addr_q.delete();
  endfunction

  function void report_gpu_done();
    // DUT: a start->done cycle completes and intr_gen captures the done event.
    rm[1].stored = 32'h1;
  endfunction

  function void clear_gpu_done();
    // DUT: INT_CLR (Reg2 bit0) W1C write deasserts intr_gen.irq_o.
    rm[1].stored = 32'h0;
  endfunction

  // Expected readback for a given register index, derived from the model.
  // Live regs expose only bit0 (axil_control.sv:395-396 forces bits[31:1] to 0).
  function logic [31:0] expected_readback(int idx);
    if (idx < 0 || idx >= NUM_REGS) return 32'h0;
    if (rm[idx].is_live) return {31'h0, rm[idx].stored[0]};
    return rm[idx].stored;
  endfunction

  virtual function void write_ctrl(axi4lite_seq_item item);
    int idx = item.addr >> 2;

    if (item.op == WRITE) begin
      ctrl_write_count++;
      if (idx >= NUM_REGS) begin
        `uvm_info("SCB_CTRL", $sformatf("Write to out-of-range offset 0x%0h dropped", item.addr), UVM_MEDIUM)
        // Capture the observed OOR response contract (item 2): always report it,
        // and enforce it only if the test opted in after the W6 decision.
        `uvm_info("SCB_CTRL", $sformatf("OOR Write 0x%0h observed resp=%b (en_oob_resp=%b, exp_when_en=%b)", item.addr, item.resp, en_oob_resp, oob_exp_resp), UVM_LOW)
        if (en_oob_resp && (item.resp !== oob_exp_resp)) begin
          `uvm_error("SCB_CTRL", $sformatf("OOR Write 0x%0h resp=%b != expected OOR resp=%b", item.addr, item.resp, oob_exp_resp))
        end
        return;
      end
      // In-range write to a defined register MUST complete with OKAY per the
      // AXI4-Lite protocol. Check this before the is_live early-return so the
      // live Reg1 (STATUS) write path is covered too.
      if (item.resp !== RESP_OKAY) begin
        `uvm_error("SCB_CTRL", $sformatf("Write to Reg[%0d] at 0x%0h returned resp=%b, expected OKAY=%b", idx, item.addr, item.resp, RESP_OKAY))
      end
      if (rm[idx].is_live) begin
        // Live register (Reg1 STATUS): CPU writes are dropped by the DUT.
        `uvm_info("SCB_CTRL", $sformatf("Write to live Reg[%0d] dropped; stored=%b", idx, rm[idx].stored), UVM_MEDIUM)
        return;
      end
      // Apply AXI4-Lite WSTRB byte-select: only the strobed bytes are written,
      // the non-strobed bytes keep their prior value. AXI4-Lite (IHI 0022)
      // requires a compliant slave to honor WSTRB. (The DUT's gpu_ctrl_regfile
      // currently writes the full word and ignores wb_sel; this is the intended
      // contract we assert here — a partial-write test will fail against the
      // DUT until it honors WSTRB. Contract deferred to W6.)
      for (int b = 0; b < 4; b++)
        if (item.strb[b]) rm[idx].stored[b*8 +: 8] = item.data[b*8 +: 8];
      // Apply the per-register write mask, then the DUT's W1C/self-clear for
      // INT_CLR (Reg2): writing bit0 clears the gpu_done interrupt
      // (intr_clr_gpu_done_o = registers[2][0], axil_control.sv:358) and the
      // whole register self-clears on any nonzero write (axil_control.sv:399).
      rm[idx].stored = rm[idx].stored & rm[idx].wmask;
      `uvm_info("SCB_CTRL", $sformatf("Write Reg[%0d] = %h (mask %h)", idx, rm[idx].stored, rm[idx].wmask), UVM_MEDIUM)
      if (idx == 2) begin
        if (item.data[0]) clear_gpu_done();
        rm[idx].stored = 32'h0;
      end
    end else begin
      logic [31:0] expected = expected_readback(idx);
      ctrl_check_count++;
      // In-range read (idx < NUM_REGS) to a defined register MUST complete with
      // OKAY per the AXI4-Lite protocol. OOR reads (idx >= NUM_REGS) are
      // deliberately left here for item 2's configurable OOR contract and are
      // checked for response separately.
      if (idx < NUM_REGS && item.resp !== RESP_OKAY) begin
        `uvm_error("SCB_CTRL", $sformatf("Read Reg[%0d] at 0x%0h returned resp=%b, expected OKAY=%b", idx, item.addr, item.resp, RESP_OKAY))
      end
      // OOR read (item 2): keep the data==0 expectation (expected_readback
      // returns 0), always report the observed resp, and enforce only if the
      // test opted in after the W6 decision.
      if (idx >= NUM_REGS) begin
        `uvm_info("SCB_CTRL", $sformatf("OOR Read  0x%0h observed resp=%b (en_oob_resp=%b, exp_when_en=%b)", item.addr, item.resp, en_oob_resp, oob_exp_resp), UVM_LOW)
        if (en_oob_resp && (item.resp !== oob_exp_resp)) begin
          `uvm_error("SCB_CTRL", $sformatf("OOR Read 0x%0h resp=%b != expected OOR resp=%b", item.addr, item.resp, oob_exp_resp))
        end
      end
      if (item.data !== expected) begin
        `uvm_error("SCB_CTRL", $sformatf("Mismatch at Reg[%0d]: Exp %h, Got %h", idx, expected, item.data))
      end else begin
        `uvm_info("SCB_CTRL", $sformatf("Match at Reg[%0d]: %h", idx, item.data), UVM_MEDIUM)
      end
    end
  endfunction

  virtual function void write_dma_req(pipe_item item);
    logic [31:0] byte_addr;
    dma_req_count++;
    byte_addr = item.addr * 4 + get_dma_input_offset();
    exp_dma_addr_q.push_back(byte_addr);
    `uvm_info("SCB_DMA", $sformatf("DMA Req %0d: Word Addr %h -> Byte Addr %h", dma_req_count, item.addr, byte_addr), UVM_MEDIUM)
  endfunction

  virtual function void write_dma_rsp(pipe_item item);
    logic [31:0] mem_addr;
    logic [31:0] expected;
    dma_rsp_count++;
    if (exp_dma_addr_q.size() > 0) begin
      mem_addr = exp_dma_addr_q.pop_front();
      expected = mem_model.read(mem_addr);
      if (item.data !== expected) begin
        `uvm_error("SCB_DMA", $sformatf("DMA Data Mismatch for mem_addr %h: Exp %h, Got %h", mem_addr, expected, item.data))
      end else begin
        `uvm_info("SCB_DMA", $sformatf("DMA Match for mem_addr %h: %h", mem_addr, item.data), UVM_MEDIUM)
      end
    end else begin
      `uvm_error("SCB_DMA", $sformatf("Unexpected DMA response: data %h", item.data))
    end
  endfunction

  function void check_phase(uvm_phase phase);
    // Only enforce counts the test explicitly opted into. Tests that want an
    // exact transaction count set expected_ctrl_rd / expected_dma_rsp.
    if (expected_ctrl_rd >= 0 && ctrl_check_count != expected_ctrl_rd) begin
      `uvm_error("SCB_CHECK", $sformatf("Expected %0d CTRL read checks, got %0d", expected_ctrl_rd, ctrl_check_count))
    end

    if (expected_dma_rsp >= 0 && dma_rsp_count != expected_dma_rsp) begin
      `uvm_error("SCB_CHECK", $sformatf("Expected %0d DMA responses, got %0d", expected_dma_rsp, dma_rsp_count))
    end

    if (exp_dma_addr_q.size() != 0) begin
      `uvm_error("SCB_CHECK", $sformatf("Unfinished DMA requests in queue: %0d", exp_dma_addr_q.size()))
    end
  endfunction

  function void report_phase(uvm_phase phase);
    `uvm_info("SCB_REPORT", $sformatf("=== Summary: CTRL Checks: %0d, DMA Reqs: %0d, DMA Rsps: %0d ===", ctrl_check_count, dma_req_count, dma_rsp_count), UVM_LOW)
  endfunction

endclass

`endif
