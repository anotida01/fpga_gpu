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

  int dma_req_count = 0;
  int dma_rsp_count = 0;
  int ctrl_check_count = 0;
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
      if (idx < 5) begin
        logic [31:0] mask = 32'hFFFFFFFF;
        if (idx == 1) mask = 32'h1;
        regs[idx] = item.data & mask;
        if (idx == 3) dma_input_offset = regs[3];
        `uvm_info("SCB_CTRL", $sformatf("Write Reg[%0d] = %h (mask %h)", idx, regs[idx], mask), UVM_MEDIUM)
        // Auto-clear Reg2
        if (idx == 2) regs[idx] = 0; 
      end
    end else begin
      int idx = item.addr >> 2;
      logic [31:0] expected = (idx < 5) ? regs[idx] : 32'h0;
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
    if (ctrl_check_count != 5) begin
      `uvm_error("SCB_CHECK", $sformatf("Expected 5 CTRL read checks, got %0d", ctrl_check_count))
    end
    if (dma_rsp_count != 4) begin
      `uvm_error("SCB_CHECK", $sformatf("Expected 4 DMA responses, got %0d", dma_rsp_count))
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
