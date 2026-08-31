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
  
  // Register Model State
  logic [31:0] regs[5];
  logic [31:0] dma_input_offset;
  // Reg1 (STATUS) bit0 is a LIVE read-only mirror of the gpu_done interrupt
  // (intr_gen.irq_o), not a stored register. Writes to Reg1 are dropped by the
  // DUT (axil_control.sv:395-396). This field is what the DUT presents on
  // readback and is updated by the test via set_status_gpu_done() to mirror
  // the interrupt state (set by a start->done cycle, cleared by INT_CLR/reset).
  logic [31:0] status_gpu_done = 32'h0;

  int dma_req_count = 0;
  int dma_rsp_count = 0;
  int ctrl_check_count = 0;
  int ctrl_write_count = 0;
  int expected_ctrl_rd = -1; // -1 means default/unspecified, otherwise enforce exact count
  int expected_dma_rsp = -1; // -1 means default/unspecified, otherwise enforce exact count
  logic [31:0] exp_dma_addr_q[$];

  `uvm_component_utils(axfe_scoreboard)

  function new(string name, uvm_component parent);
    super.new(name, parent);
    ctrl_export    = new("ctrl_export", this);
    dma_req_export = new("dma_req_export", this);
    dma_rsp_export = new("dma_rsp_export", this);
    for(int i=0; i<5; i++) regs[i] = 0;
    dma_input_offset = 0;
  endfunction

  virtual function void write_ctrl(axi4lite_seq_item item);
    if (item.op == WRITE) begin
      int idx = item.addr >> 2;
      ctrl_write_count++;
      if (idx == 1) begin
        // Reg1 (STATUS) is read-only; CPU writes are dropped by the DUT.
        `uvm_info("SCB_CTRL", $sformatf("Write to Reg[1] (STATUS, read-only) dropped; status_gpu_done=%b", status_gpu_done), UVM_MEDIUM)
        return;
      end
      if (idx < 5) begin
        logic [31:0] mask = 32'hFFFFFFFF;
        regs[idx] = item.data & mask;
        if (idx == 3) dma_input_offset = regs[3];
        `uvm_info("SCB_CTRL", $sformatf("Write Reg[%0d] = %h (mask %h)", idx, regs[idx], mask), UVM_MEDIUM)
        // Auto-clear Reg2
        if (idx == 2) regs[idx] = 0;
      end
    end else begin
      int idx = item.addr >> 2;
      logic [31:0] expected;
      if (idx == 1) expected = status_gpu_done[31:0]; // live interrupt status
      else         expected = (idx < 5) ? regs[idx] : 32'h0;
      ctrl_check_count++;
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
    byte_addr = item.addr * 4 + dma_input_offset;
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
    `uvm_info("SCB_REPORT", $sformatf("=== Summary: CTRL Checks: %0d, DMA Reqs: %0d, DMA Rsps: %0d ===", 
               ctrl_check_count, dma_req_count, dma_rsp_count), UVM_LOW)
  endfunction

endclass

`endif
