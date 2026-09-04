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
  int ram_write_count  = 0;
  int ram_check_count  = 0;
  int oob_count        = 0;
  int expected_ctrl_rd = -1; // -1 = unspecified, otherwise enforce exact count
  int expected_ctrl_wr = -1; // -1 = unspecified, otherwise enforce exact count

  `uvm_component_utils(gpu_scoreboard)

  function new(string name, uvm_component parent);
    super.new(name, parent);
    host_export = new("host_export", this);
    model_reset();
  endfunction

  // --- Register-model event hooks (mirror axfe; for the future start/done tests)
  function void model_reset();
    for (int i = 0; i < NUM_REGS; i++) begin
      rm[i].is_live = (i == 1);
      rm[i].wmask   = (i == 1) ? 32'h1 : 32'hFFFFFFFF;
      rm[i].stored  = 32'h0;
    end
  endfunction

  function void report_gpu_done();
    rm[1].stored = 32'h1; // STATUS[0] reflects the latched gpu_done interrupt
  endfunction

  function void clear_gpu_done();
    rm[1].stored = 32'h0; // INT_CLR W1C deasserts intr_gen.irq_o
  endfunction

  function logic [31:0] expected_readback(int idx);
    if (idx < 0 || idx >= NUM_REGS) return 32'h0;
    if (rm[idx].is_live) return {31'h0, rm[idx].stored[0]};
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
      if (idx == 2) begin // INT_CLR: bit0 W1C clears the interrupt, then self-clears
        if (item.data[0]) clear_gpu_done();
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
        `uvm_info("SCB_CTRL", $sformatf("Match at ctrl Reg[%0d] (0x%0h): %h", idx, item.addr, item.data), UVM_MEDIUM)
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
      `uvm_info("SCB_RAM", $sformatf("RAM Write 0x%0h = %h", item.addr, item.data), UVM_MEDIUM)
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
          `uvm_info("SCB_RAM", $sformatf("RAM Match at 0x%0h: %h", item.addr, item.data), UVM_MEDIUM)
      end else begin
        `uvm_info("SCB_RAM", $sformatf("RAM read at 0x%0h (unseeded, reported only): %h", item.addr, item.data), UVM_MEDIUM)
      end
    end
  endfunction

  function void check_phase(uvm_phase phase);
    if (expected_ctrl_rd >= 0 && ctrl_check_count != expected_ctrl_rd)
      `uvm_error("SCB_CHECK", $sformatf("Expected %0d ctrl read checks, got %0d", expected_ctrl_rd, ctrl_check_count))
    if (expected_ctrl_wr >= 0 && ctrl_write_count != expected_ctrl_wr)
      `uvm_error("SCB_CHECK", $sformatf("Expected %0d ctrl writes, got %0d", expected_ctrl_wr, ctrl_write_count))
  endfunction

  function void report_phase(uvm_phase phase);
    `uvm_info("SCB_REPORT", $sformatf("=== Summary: CTRL Writes: %0d, CTRL Read-Checks: %0d, RAM Writes: %0d, RAM Read-Checks: %0d, OOR: %0d ===",
                ctrl_write_count, ctrl_check_count, ram_write_count, ram_check_count, oob_count), UVM_LOW)
  endfunction

endclass

`endif
